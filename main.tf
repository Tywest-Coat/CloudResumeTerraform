terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "test-bucket" {
  bucket = "test-ter-bucket-tawestcoat"

  tags = {
    Name = "testterbuckettawestcoat"
  }
}

resource "aws_s3_bucket_website_configuration" "test-bucket" {
  bucket = aws_s3_bucket.test-bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

resource "aws_s3_bucket_public_access_block" "test-bucket" {
  bucket = aws_s3_bucket.test-bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.test-bucket.id
  key          = "index.html"
  source       = "index.html"
  content_type = "text/html"
}

resource "aws_s3_bucket_policy" "test-bucket-policy" {
  bucket = aws_s3_bucket.test-bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource = [
          "${aws_s3_bucket.test-bucket.arn}",
          "${aws_s3_bucket.test-bucket.arn}/*"
        ]
      }
    ]
  })
}

# Declare the resource for the Route 53 hosted zone
resource "aws_route53_zone" "my_zone" {
  name = "tylerwestcoat.com"
}

# Declare the data source for the Route 53 hosted zone
data "aws_route53_zone" "my_zone" {
  zone_id = "Z08436631AU8QV3Y678NV" # Replace with your actual hosted zone ID
}



resource "aws_acm_certificate" "test_certificate" {
  domain_name       = "test.tylerwestcoat.com"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "test.tylerwestcoat.com"
  }
}

resource "aws_route53_record" "test_certificate_validation" {
  for_each = {
    for dvo in aws_acm_certificate.test_certificate.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  name    = each.value.name
  type    = each.value.type
  zone_id = data.aws_route53_zone.my_zone.zone_id
  records = [each.value.record]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "test_certificate" {
  certificate_arn         = aws_acm_certificate.test_certificate.arn
  validation_record_fqdns = [for record in aws_route53_record.test_certificate_validation : record.fqdn]
}

resource "aws_cloudfront_distribution" "test_distribution" {
  origin {
    domain_name = aws_s3_bucket.test-bucket.bucket_regional_domain_name
    origin_id   = "S3-test-bucket"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.test_origin_access_identity.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for test.tylerwestcoat.com"
  default_root_object = "index.html"

  aliases = ["test.tylerwestcoat.com"]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-test-bucket"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn            = aws_acm_certificate.test_certificate.arn
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = "TLSv1.2_2019"
    cloudfront_default_certificate = false
  }

  tags = {
    Name = "test.tylerwestcoat.com"
  }
}

resource "aws_cloudfront_origin_access_identity" "test_origin_access_identity" {
  comment = "Origin Access Identity for test.tylerwestcoat.com"
}

# Route 53 Record for CloudFront Distribution
resource "aws_route53_record" "test_website_record" {
  zone_id = data.aws_route53_zone.my_zone.zone_id
  name    = "test.tylerwestcoat.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.test_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.test_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}