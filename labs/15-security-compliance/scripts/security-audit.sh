#!/bin/bash
# ============================================================
# Cloud Security Audit Script
# Scans for common security misconfigurations in AWS
# Author: Jenella Awo
# ============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
PASS=0
FAIL=0
WARN=0

echo "============================================"
echo "  AWS Cloud Security Audit"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"
echo ""

# --- Check 1: Public S3 Buckets ---
echo -e "${YELLOW}[CHECK 1] Scanning for public S3 buckets...${NC}"
PUBLIC_BUCKETS=$(aws s3api list-buckets --query 'Buckets[].Name' --output text | tr '\t' '\n' | while read bucket; do
  acl=$(aws s3api get-bucket-acl --bucket "$bucket" 2>/dev/null | grep -c '"URI": "http://acs.amazonaws.com/groups/global/AllUsers"' || true)
  if [ "$acl" -gt 0 ]; then echo "$bucket"; fi
done)
if [ -z "$PUBLIC_BUCKETS" ]; then
  echo -e "  ${GREEN}PASS${NC} — No public S3 buckets found"
  ((PASS++))
else
  echo -e "  ${RED}FAIL${NC} — Public buckets: $PUBLIC_BUCKETS"
  ((FAIL++))
fi

# --- Check 2: Unencrypted EBS Volumes ---
echo -e "${YELLOW}[CHECK 2] Scanning for unencrypted EBS volumes...${NC}"
UNENCRYPTED=$(aws ec2 describe-volumes --query 'Volumes[?Encrypted==`false`].VolumeId' --output text)
if [ -z "$UNENCRYPTED" ]; then
  echo -e "  ${GREEN}PASS${NC} — All EBS volumes are encrypted"
  ((PASS++))
else
  COUNT=$(echo "$UNENCRYPTED" | wc -w | tr -d ' ')
  echo -e "  ${RED}FAIL${NC} — $COUNT unencrypted EBS volumes found"
  ((FAIL++))
fi

# --- Check 3: Open Security Groups (0.0.0.0/0 on SSH/RDP) ---
echo -e "${YELLOW}[CHECK 3] Scanning for security groups open to 0.0.0.0/0 on SSH/RDP...${NC}"
OPEN_SG=$(aws ec2 describe-security-groups \
  --query 'SecurityGroups[?IpPermissions[?((FromPort==`22` || FromPort==`3389`) && IpRanges[?CidrIp==`0.0.0.0/0`])]].[GroupId,GroupName]' \
  --output text)
if [ -z "$OPEN_SG" ]; then
  echo -e "  ${GREEN}PASS${NC} — No security groups open to the world on SSH/RDP"
  ((PASS++))
else
  echo -e "  ${RED}FAIL${NC} — Open security groups found:"
  echo "  $OPEN_SG"
  ((FAIL++))
fi

# --- Check 4: IAM Users Without MFA ---
echo -e "${YELLOW}[CHECK 4] Checking IAM users without MFA enabled...${NC}"
NO_MFA=$(aws iam generate-credential-report > /dev/null 2>&1; sleep 2; \
  aws iam get-credential-report --query 'Content' --output text | base64 -d | \
  awk -F',' 'NR>1 && $4=="true" && $8=="false" {print $1}')
if [ -z "$NO_MFA" ]; then
  echo -e "  ${GREEN}PASS${NC} — All console users have MFA enabled"
  ((PASS++))
else
  echo -e "  ${RED}FAIL${NC} — Users without MFA: $NO_MFA"
  ((FAIL++))
fi

# --- Check 5: Access Keys Older Than 90 Days ---
echo -e "${YELLOW}[CHECK 5] Checking for access keys older than 90 days...${NC}"
OLD_KEYS=$(aws iam get-credential-report --query 'Content' --output text | base64 -d | \
  awk -F',' 'NR>1 && $9=="true" {print $1, $10}' | while read user date; do
    if [ -n "$date" ] && [ "$date" != "N/A" ]; then
      key_age=$(( ($(date +%s) - $(date -j -f "%Y-%m-%dT%H:%M:%S+00:00" "$date" +%s 2>/dev/null || echo $(date +%s))) / 86400 ))
      if [ "$key_age" -gt 90 ]; then echo "$user ($key_age days)"; fi
    fi
  done 2>/dev/null)
if [ -z "$OLD_KEYS" ]; then
  echo -e "  ${GREEN}PASS${NC} — No access keys older than 90 days"
  ((PASS++))
else
  echo -e "  ${YELLOW}WARN${NC} — Old access keys: $OLD_KEYS"
  ((WARN++))
fi

# --- Check 6: CloudTrail Enabled ---
echo -e "${YELLOW}[CHECK 6] Verifying CloudTrail is enabled...${NC}"
TRAILS=$(aws cloudtrail describe-trails --query 'trailList[?IsMultiRegionTrail==`true`].Name' --output text)
if [ -n "$TRAILS" ]; then
  echo -e "  ${GREEN}PASS${NC} — Multi-region CloudTrail active: $TRAILS"
  ((PASS++))
else
  echo -e "  ${RED}FAIL${NC} — No multi-region CloudTrail found"
  ((FAIL++))
fi

# --- Summary ---
echo ""
echo "============================================"
echo "  AUDIT SUMMARY"
echo "============================================"
echo -e "  ${GREEN}PASSED:${NC}  $PASS"
echo -e "  ${RED}FAILED:${NC}  $FAIL"
echo -e "  ${YELLOW}WARNINGS:${NC} $WARN"
echo "============================================"

if [ "$FAIL" -gt 0 ]; then
  echo -e "\n${RED}ACTION REQUIRED: $FAIL security issues need remediation${NC}"
  exit 1
else
  echo -e "\n${GREEN}All critical checks passed.${NC}"
fi
