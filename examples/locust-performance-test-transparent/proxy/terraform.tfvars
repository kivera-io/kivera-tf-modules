proxy_instance_type          = "c5d.xlarge"
proxy_min_asg_size           = 6
proxy_max_asg_size           = 15
cache_enabled                = false
ec2_key_pair                 = "kivera-poc-keypair"
s3_bucket                    = "kivera-poc-deployment"
cross_zone_lb                = true
proxy_credentials_secret_arn = "arn:aws:secretsmanager:ap-southeast-2:326190351503:secret:kivera-perf-test-credentials-PiGa5W"
proxy_private_key_secret_arn = "arn:aws:secretsmanager:ap-southeast-2:326190351503:secret:kivera-perf-test-private-key-ePpYBq"
proxy_public_cert            = <<-EOT
-----BEGIN CERTIFICATE-----
MIIFnTCCA4WgAwIBAgIUSF7DjAysFwNuxH0o4lH/xV9dDrgwDQYJKoZIhvcNAQEL
BQAwXjELMAkGA1UEBhMCQVUxDDAKBgNVBAgMA05TVzEPMA0GA1UEBwwGU3lkbmV5
MQ8wDQYDVQQKDAZLaXZlcmExCzAJBgNVBAsMAklUMRIwEAYDVQQDDAlraXZlcmEu
aW8wHhcNMjQwMTA0MDQwMjMyWhcNMzQwMTAxMDQwMjMyWjBeMQswCQYDVQQGEwJB
VTEMMAoGA1UECAwDTlNXMQ8wDQYDVQQHDAZTeWRuZXkxDzANBgNVBAoMBktpdmVy
YTELMAkGA1UECwwCSVQxEjAQBgNVBAMMCWtpdmVyYS5pbzCCAiIwDQYJKoZIhvcN
AQEBBQADggIPADCCAgoCggIBAKZ4asLSOFMUU154GsHRI3j5oMkDvV98L4x8+Cdg
KqUjICcLxBm461UDDZis1wWxg7j4EAhGMxgAZFuQ9Yncp01otvizE6cur3NcwArJ
r0Jf6h0LiEH7UfTnJ0+g8nH3k5ncHMDxGNDz+zNs19WDNAJZOHKVG251N3I5yNYB
e1IuofAlSGo/TBlkOKkpk5WyWIRbvMy2Zd4Gl/q8yQust6KIY3PauUA66ZZCPOj8
eeZ7cH1oUj/5e0CIXr7mKccxKMuObMt5LFoge7JKxuJmILA/EFCaoq9LqGwy718Q
cjQUsXbzQc9hXdf8UHMll/Ie9wjj4lJHlBshrObaKZnbTZ68AUiRTMSNO6CWcUFX
Sh9Zl0Dy7ooPQRR6ZARLRlFFlSNJWtW9q0UKlw02vqiCBju9dmAnG4lmfFU8KetQ
aCA9802DAtZcnsFMnKFrQx9vW20B+YDJraGLfyxIsc2nUgxDejwURVSRe6w0g8UI
AaYwjc0uEtYksGHInOHYvVG0V+MEztj+OZuBCdTS2QxTsuFZDPRKOmyXkpV2gixR
ij0csTv5N42IXhWiiFhtyCj2adQdcpc7+Si7CfQjwA20ol6VyRSIx2jiA+d6rh2L
Ocz+DKohar4MEu0XLyROZPvd/c+uKKxKHRl2MCNvDXv/0mfKomasFpaecnS0j8u5
1gwBAgMBAAGjUzBRMB0GA1UdDgQWBBTSLAzNDaEEa6D4T/uhPR2k9bq65zAfBgNV
HSMEGDAWgBTSLAzNDaEEa6D4T/uhPR2k9bq65zAPBgNVHRMBAf8EBTADAQH/MA0G
CSqGSIb3DQEBCwUAA4ICAQBUnOGpb2VPCG2eJLXviReFjnnye3QWDSb3fvYXTJHY
uZOvpSGZifdTSlPaGoVEqKjtUJD3khwQayLVzSXJavq/M7nwgNcGVfoRjJYz9rvX
hW4y9KlpX8wi6H0B2REv5C8DwCh44wPnwHW2pw0kGgZoPnllCxPHbC79e2zwlok0
CR0JFZJXAfYPIWG1iE6bFu5GN3X6T1L6sBY+oLcNbAcgG7W3ThruBS1fqx7DzhlS
jAu3W2Ff5pScHAOnYPesfx7RMp6TIWP3hZ3BFzewOZS0ZqbLeEcRDNiAB35JtCje
eMIhJxikJ0vc2PoExUYzKYNGPv00xvghxWYp5lYqIj9KATO+6EIEr7hGkRXJSrBl
B+HXOlX8y+ryJvCb5hNMODuGJYqAJPrspaVTydlz7Gspa6F/VT+EMWXj1TSel87t
HTTscs4238iVoSkjoNJPvs+mAh7jOPA/XwIkpkft9ZgynvI6YPu9FzH7Uu8hdceB
O0tTg3RbxwAMW1eGZJpdIGyh6ZQ8BHrdBwVM9oxETk2Dmj51wjT460FKCgpzYpsa
Vn9gYaRiyOIQrOQgulw3BUao/9rWlojUwI1TiwUhh3bnaoFyGegj9h4AbaMDhdHh
a8K+KeK12xh4K2OfEmHjncbhx9Fhi5AdEcT6KEqsMDtZ8SQm2nlP52YzGVXmn0bn
zg==
-----END CERTIFICATE-----
EOT
