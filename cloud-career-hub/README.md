# Cloud Career Hub — SA/SE Career Platform

> **Builder:** Vanessa Awo · Solutions Architect | Solutions Engineer  
> **Stack:** React · Vite · Firebase · Google Gemini AI · GitHub Pages  
> **Live Site:** https://denvanholdings-cloud.github.io/sa-career

---

## Overview

A full-stack career platform built to support SA and SE job targeting — demonstrating the ability to scope, build, and ship a working product end-to-end (a core SE/pre-sales skill).

---

## Features

- **Firebase Authentication** — secure login with role-based access control (admin vs public)
- **AI-Powered Resume Writer** — Google Gemini 2.0 Flash generates tailored resume bullets based on job description input
- **Dual Resume Toggle** — switch between SA-targeted and SE/Pre-Sales-targeted resume versions
- **Calendar with PIN Lock** — protected scheduling view for interview tracking
- **Admin-Protected Pages** — sensitive content gated behind RBAC
- **Automated Deployment** — GitHub Actions `gh-pages` pipeline for zero-touch deploys

---

## Architecture

```
Browser
  └── React (Vite) SPA
        ├── Firebase Auth  ──────────────── Google Identity
        ├── Google Gemini API  ─────────── AI resume generation
        ├── React Router  ──────────────── Client-side routing
        └── GitHub Pages  ──────────────── Static hosting via gh-pages CI/CD
```

---

## SA/SE Relevance

| Skill | Demonstrated |
|---|---|
| POC delivery | Scoped and shipped a full working product |
| AI integration | Consumed Gemini API for a real use case |
| Auth + RBAC | Firebase Auth with role-gated pages |
| CI/CD | GitHub Actions automated deploy pipeline |
| Stakeholder framing | Dual resume toggle shows SA vs SE positioning |

---

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | React 18, Vite, Tailwind CSS |
| Auth | Firebase Authentication |
| AI | Google Gemini 2.0 Flash API |
| Hosting | GitHub Pages |
| CI/CD | GitHub Actions (`gh-pages`) |
