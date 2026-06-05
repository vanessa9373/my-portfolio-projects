module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'scope-enum': [2, 'always', [
      'api-gateway', 'user-service', 'product-service',
      'order-service', 'payment-service', 'notification-service',
      'infra', 'ci', 'docs'
    ]],
    'type-enum': [2, 'always', [
      'feat', 'fix', 'docs', 'style', 'refactor',
      'perf', 'test', 'build', 'ci', 'chore'
    ]]
  }
};
