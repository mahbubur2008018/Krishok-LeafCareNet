# Security Policy: Krishok-LeafCareNet

## Supported Versions
| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |

## Reporting a Vulnerability
The Krishok-LeafCareNet project strictly enforces credential sanitization and secure coding standards. If you discover any potential security issue, hardcoded secret, or vulnerability:

1. **Do not open a public issue.**
2. Please report the issue privately to the research repository administrators via email or GitHub Security Advisories.
3. Include details of the vulnerability, affected file paths, and proof of concept.
4. The project maintainers will investigate and release a security patch within 48 hours.

## Local Configuration Best Practices
- Never commit `lib/services/gemini_service.dart` with an embedded API key.
- Provide credentials via compile-time variables: `--dart-define=GEMINI_API_KEY=YOUR_KEY`.
- Never commit production Wi-Fi passwords in `esp32/firmware/`.