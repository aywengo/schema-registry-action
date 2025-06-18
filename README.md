# Schema Registry CI/CD Action

[![GitHub Marketplace](https://img.shields.io/badge/Marketplace-Schema%20Registry%20CI%2FCD-blue?logo=github)](https://github.com/marketplace/actions/schema-registry-cicd)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![CI](https://github.com/aywengo/schema-registry-action/workflows/CI/badge.svg)](https://github.com/aywengo/schema-registry-action/actions)

A GitHub Action for automating Schema Registry operations in your CI/CD pipeline. Supports Confluent Schema Registry, AWS Glue Schema Registry, and other compatible implementations.

## Features

- 🔄 **Schema Validation**: Validate schemas before deployment
- 🧪 **Compatibility Testing**: Check backward/forward compatibility
- 📦 **Schema Import/Export**: Deploy schemas from repository to registry
- 🔍 **Drift Detection**: Compare schemas between environments
- 📊 **Schema Documentation**: Generate docs from schemas
- 🛡️ **Security Scanning**: Check for sensitive data in schemas
- 🔔 **Notifications**: Alert teams about schema changes

## Quick Start

```yaml
- name: Schema Registry Operations
  uses: aywengo/schema-registry-action@v1
  with:
    operation: 'validate'
    registry-url: ${{ secrets.SCHEMA_REGISTRY_URL }}
    schemas-path: './schemas'
```

## Operations

### Validate Schemas

```yaml
- uses: aywengo/schema-registry-action@v1
  with:
    operation: 'validate'
    schemas-path: './schemas'
    schema-type: 'avro'  # avro, protobuf, json
```

### Check Compatibility

```yaml
- uses: aywengo/schema-registry-action@v1
  with:
    operation: 'check-compatibility'
    registry-url: ${{ secrets.SCHEMA_REGISTRY_URL }}
    subject: 'user-events-value'
    schema-file: './schemas/user-events.avsc'
    compatibility-level: 'BACKWARD'  # BACKWARD, FORWARD, FULL, NONE
```

### Deploy Schemas

```yaml
- uses: aywengo/schema-registry-action@v1
  with:
    operation: 'deploy'
    registry-url: ${{ secrets.SCHEMA_REGISTRY_URL }}
    schemas-path: './schemas'
    dry-run: 'false'
    fail-on-error: 'true'
```

### Compare Registries

```yaml
- uses: aywengo/schema-registry-action@v1
  with:
    operation: 'compare'
    source-registry: ${{ secrets.DEV_REGISTRY_URL }}
    target-registry: ${{ secrets.PROD_REGISTRY_URL }}
    output-format: 'json'  # json, table, markdown
```

### Export Schemas

```yaml
- uses: aywengo/schema-registry-action@v1
  with:
    operation: 'export'
    registry-url: ${{ secrets.SCHEMA_REGISTRY_URL }}
    output-path: './backup/schemas'
    include-versions: 'all'  # all, latest
```

## Full Example Workflow

```yaml
name: Schema Registry CI/CD

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Validate Schemas
        uses: aywengo/schema-registry-action@v1
        with:
          operation: 'validate'
          schemas-path: './schemas'
          
      - name: Lint Schemas
        uses: aywengo/schema-registry-action@v1
        with:
          operation: 'lint'
          schemas-path: './schemas'
          rules-file: './schema-rules.yaml'

  compatibility:
    runs-on: ubuntu-latest
    needs: validate
    if: github.event_name == 'pull_request'
    steps:
      - uses: actions/checkout@v3
      
      - name: Check Compatibility
        uses: aywengo/schema-registry-action@v1
        with:
          operation: 'check-compatibility'
          registry-url: ${{ secrets.PROD_REGISTRY_URL }}
          schemas-path: './schemas'
          compatibility-level: 'BACKWARD'

  deploy:
    runs-on: ubuntu-latest
    needs: [validate, compatibility]
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v3
      
      - name: Deploy to Production
        uses: aywengo/schema-registry-action@v1
        with:
          operation: 'deploy'
          registry-url: ${{ secrets.PROD_REGISTRY_URL }}
          schemas-path: './schemas'
          create-subjects: 'true'
          normalize-schemas: 'true'
          
      - name: Generate Documentation
        uses: aywengo/schema-registry-action@v1
        with:
          operation: 'generate-docs'
          schemas-path: './schemas'
          output-path: './docs/schemas'
          format: 'markdown'
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `operation` | Operation to perform | Yes | - |
| `registry-url` | Schema Registry URL | No* | - |
| `registry-type` | Registry type (confluent, aws-glue, apicurio) | No | `confluent` |
| `schemas-path` | Path to schema files | No | `./schemas` |
| `schema-file` | Single schema file | No | - |
| `subject` | Schema subject name | No | - |
| `compatibility-level` | Compatibility level | No | `BACKWARD` |
| `output-format` | Output format | No | `json` |
| `fail-on-error` | Fail action on error | No | `true` |
| `dry-run` | Perform dry run | No | `false` |
| `auth-method` | Authentication method | No | `basic` |
| `username` | Registry username | No | - |
| `password` | Registry password | No | - |
| `api-key` | API key for auth | No | - |
| `api-secret` | API secret for auth | No | - |

*Required for operations that interact with registry

## Outputs

| Output | Description |
|--------|-------------|
| `validation-result` | Validation result (success/failure) |
| `compatibility-result` | Compatibility check result |
| `deployed-schemas` | List of deployed schemas |
| `schema-diff` | Differences between schemas |
| `export-path` | Path to exported schemas |

## Authentication

### Basic Authentication
```yaml
- uses: aywengo/schema-registry-action@v1
  with:
    registry-url: ${{ secrets.SCHEMA_REGISTRY_URL }}
    username: ${{ secrets.REGISTRY_USERNAME }}
    password: ${{ secrets.REGISTRY_PASSWORD }}
```

### API Key Authentication
```yaml
- uses: aywengo/schema-registry-action@v1
  with:
    registry-url: ${{ secrets.SCHEMA_REGISTRY_URL }}
    auth-method: 'api-key'
    api-key: ${{ secrets.API_KEY }}
    api-secret: ${{ secrets.API_SECRET }}
```

### OAuth/Token Authentication
```yaml
- uses: aywengo/schema-registry-action@v1
  with:
    registry-url: ${{ secrets.SCHEMA_REGISTRY_URL }}
    auth-method: 'oauth'
    token: ${{ secrets.OAUTH_TOKEN }}
```

## Schema Organization

Recommended directory structure:

```
schemas/
├── avro/
│   ├── user-events.avsc
│   ├── order-events.avsc
│   └── product-events.avsc
├── protobuf/
│   ├── analytics.proto
│   └── monitoring.proto
├── json/
│   └── config-schema.json
└── schema-rules.yaml
```

## Advanced Configuration

### Custom Rules File
```yaml
# schema-rules.yaml
rules:
  naming:
    pattern: '^[a-z]+(-[a-z]+)*$'
    message: 'Schema names must be kebab-case'
  
  fields:
    required:
      - id
      - timestamp
      - version
    
  documentation:
    required: true
    minLength: 20
    
  compatibility:
    level: BACKWARD
    allowBreaking: false
```

### Multi-Environment Deployment
```yaml
- name: Deploy to Environment
  uses: aywengo/schema-registry-action@v1
  with:
    operation: 'deploy'
    registry-url: ${{ secrets[format('{0}_REGISTRY_URL', env.ENVIRONMENT)] }}
    schemas-path: './schemas'
    subject-prefix: '${{ env.ENVIRONMENT }}-'
```

## Troubleshooting

### Common Issues

1. **Authentication Failures**
   - Verify credentials are correctly set in secrets
   - Check if registry requires specific auth headers

2. **Compatibility Errors**
   - Review compatibility rules in your registry
   - Use `compatibility-level: NONE` for testing

3. **Network Issues**
   - Ensure GitHub Actions can reach your registry
   - Check if VPN or IP whitelisting is required

### Debug Mode

Enable debug logging:
```yaml
- uses: aywengo/schema-registry-action@v1
  with:
    operation: 'deploy'
    debug: 'true'
    verbose: 'true'
```

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

- 📚 [Documentation](https://github.com/aywengo/schema-registry-action/wiki)
- 🐛 [Issue Tracker](https://github.com/aywengo/schema-registry-action/issues)
- 💬 [Discussions](https://github.com/aywengo/schema-registry-action/discussions)

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history.

---

Made with ❤️ for Kafka Community