# HttpCraft Examples

This directory contains example configurations and documentation to help you learn and use HttpCraft effectively.

## 📁 Directory Structure

```
examples/
├── README.md                           # This file
├── quick-start/                        # Basic getting started examples
│   ├── 01_basic_config.yaml           # Simple API configuration
│   ├── 02_with_variables.yaml         # Variables and profiles
│   └── 03_simple_chain.yaml           # Basic request chaining
├── features/                           # Feature-specific examples
│   ├── profiles/
│   │   ├── multiple_profiles.yaml      # Multiple profile usage
│   │   └── enhanced_merging.yaml       # Phase 13 enhanced merging
│   ├── variables/
│   │   ├── dynamic_variables.yaml      # Built-in dynamic variables
│   │   └── secrets.yaml                # Secret variable usage
│   ├── chains/
│   │   ├── simple_chain.yaml           # Basic chaining
│   │   └── multi_api_chain.yaml        # Cross-API chaining
│   ├── plugins/
│   │   ├── basic_plugin.yaml           # Basic plugin usage
│   │   ├── parameterized_functions.yaml # Plugin parameterized functions
│   │   └── npm_plugin.yaml             # NPM plugin usage
│   ├── oauth2/
│   │   ├── builtin_oauth2.yaml         # Built-in OAuth2 plugin
│   │   ├── client_credentials.yaml     # Client credentials flow
│   │   └── interactive_oauth2.yaml     # Interactive authorization flow
│   └── advanced/
│       ├── custom_secret_resolver.yaml # Custom secret resolution
│       └── modular_setup/              # Modular configuration
├── plugins/                            # Example plugin implementations
│   ├── README.md                       # Plugin development guide
│   ├── dummyAuthPlugin.js              # Basic authentication plugin
│   ├── xmlToJsonPlugin.js              # XML response transformation
│   ├── cachePlugin.js                  # Response caching
│   ├── testSecretProvider.js           # Test secret provider
│   └── vaultSecretProvider.js          # HashiCorp Vault integration
├── schemas/                            # Schema and validation examples
│   └── schema_example.yaml             # YAML schema validation example
├── configs/                            # Specialized configuration examples
│   └── xml_api.yaml                    # XML API handling example
└── comprehensive_example.yaml          # Complete feature showcase
```

## 🚀 Quick Start Examples

Start here if you're new to HttpCraft:

1. **[Basic Configuration](quick-start/01_basic_config.yaml)** - Simple API setup
2. **[Variables and Profiles](quick-start/02_with_variables.yaml)** - Dynamic configuration
3. **[Simple Chain](quick-start/03_simple_chain.yaml)** - Request chaining basics

## 🎯 Feature Examples

Explore specific HttpCraft features:

### Profiles and Variables

- **[Multiple Profiles](features/profiles/multiple_profiles.yaml)** - Using multiple profiles together
- **[Enhanced Profile Merging](features/profiles/enhanced_merging.yaml)** - Phase 13 additive merging
- **[Dynamic Variables](features/variables/dynamic_variables.yaml)** - Built-in timestamp, GUID, etc.
- **[Secrets Management](features/variables/secrets.yaml)** - Secure variable handling

### Request Chaining

- **[Simple Chain](features/chains/simple_chain.yaml)** - Basic step-by-step requests
- **[Multi-API Chain](features/chains/multi_api_chain.yaml)** - Chaining across different APIs

### Plugin System

- **[Basic Plugin Usage](features/plugins/basic_plugin.yaml)** - Local plugin integration
- **[Parameterized Functions](features/plugins/parameterized_functions.yaml)** - Plugin functions with arguments
- **[NPM Plugin](features/plugins/npm_plugin.yaml)** - Installing plugins from npm

### OAuth2 Authentication

- **[Built-in OAuth2](features/oauth2/builtin_oauth2.yaml)** - Using the built-in OAuth2 plugin
- **[Client Credentials](features/oauth2/client_credentials.yaml)** - Server-to-server authentication
- **[Interactive OAuth2](features/oauth2/interactive_oauth2.yaml)** - User authentication flows

### Advanced Features

- **[Custom Secret Resolver](features/advanced/custom_secret_resolver.yaml)** - Plugin-based secret resolution
- **[Modular Setup](features/advanced/modular_setup/)** - Large-scale configuration organization

## 🔌 Plugin Examples

The `plugins/` directory contains ready-to-use plugin implementations:

- **Authentication Plugins**: JWT token management, OAuth2 flows
- **Data Transformation**: XML to JSON conversion, response formatting
- **Integrations**: HashiCorp Vault, external secret managers
- **Utilities**: Response caching, request logging

See the [Plugin Development Guide](plugins/README.md) for creating your own plugins.

## 📋 Schema Validation

HttpCraft supports YAML schema validation for your configuration files. See the [schema example](schemas/schema_example.yaml) for editor integration setup.

## 🛠 Development Setup

- **[ZSH Completion Setup](../docs/completion_setup.md)** - Tab completion installation
- **[Nix Usage Guide](../docs/nix_usage.md)** - Nix development environment

## 📖 Complete Reference

The **[Comprehensive Example](comprehensive_example.yaml)** demonstrates most HttpCraft features in a single, well-documented configuration file.

## 🎯 Getting Help

1. Start with the [Quick Start examples](quick-start/)
2. Explore [feature-specific examples](features/) for your use case
3. Check the [main README](../README.md) for complete documentation
4. Review plugin examples for extensibility

Each example file includes detailed comments explaining the configuration and usage patterns.
