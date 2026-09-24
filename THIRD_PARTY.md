# Third-Party Code

The analyzer implementation is original MoonBit code and does not vendor
third-party libraries or data files. The format follows the public Common and
Combined Log Format conventions used by Nginx and Apache HTTP Server.

Reference sources:

- Nginx `log_format` documentation: https://nginx.org/en/docs/http/ngx_http_log_module.html
- Apache HTTP Server `mod_log_config` documentation: https://httpd.apache.org/docs/2.4/mod/mod_log_config.html

No source code was ported from either project. The parser and aggregation
logic are implemented in MoonBit against `moonbitlang/core`.
