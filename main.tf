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
  region  = "ap-northeast-2"
}

locals {
  s3_bucket_name = "woomin-terraform-s3-cf-deploy"
  s3_bucket_target_directory_path = "/static"
  s3_default_object = "index.html"
}

# S3 버킷 생성
resource "aws_s3_bucket" "terraform_test" {
  bucket = local.s3_bucket_name
}

# S3 버킷 정책
data "aws_iam_policy_document" "s3_bucket_allow_all" {
  statement {
    resources     = [                           # 이런 리소스들에 대해서
      "arn:aws:s3:::${local.s3_bucket_name}",
      "arn:aws:s3:::${local.s3_bucket_name}/*"
    ]
    actions       = ["s3:GetObject"]            # S3 객체에 접근을
    principals {                                # CloudFront 서비스의
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {                                 # 다음 배포와 일치하는 것만
      test        = "StringEquals"
      variable    = "AWS:SourceArn"
      values      = [aws_cloudfront_distribution.terraform_test_distribution.arn]
    }
    effect        = "Allow"                     # 허용한다
  }
}

# S3 버킷 정책 적용
resource "aws_s3_bucket_policy" "woomin_s3_bucket_policy" {
  bucket   = aws_s3_bucket.terraform_test.id                          # 이 버킷에 대해서
  policy   = data.aws_iam_policy_document.s3_bucket_allow_all.json    # 이 정책을 사용
}

# CloudFront 배포 생성
resource "aws_cloudfront_distribution" "terraform_test_distribution" {
  origin {
    domain_name              = aws_s3_bucket.terraform_test.bucket_regional_domain_name # 원본 도메인
    origin_id                = aws_s3_bucket.terraform_test.id                          # S3 버킷 id
    origin_path              = local.s3_bucket_target_directory_path                    # S3 버킷 원본 경로
    origin_access_control_id = aws_cloudfront_origin_access_control.s3_origin.id        # S3 버킷 엑세스 제어
  }

  enabled                    = true
  default_root_object        = local.s3_default_object                                  # 기본 값 루트 객체 (루트 경로로 접근시 내려줄 객체)
  aliases                    = []                                                       # 대체 도메인 이름(CNAME)

  default_cache_behavior {
    target_origin_id         = aws_s3_bucket.terraform_test.id
    allowed_methods          = ["GET", "HEAD"]
    cached_methods           = ["GET", "HEAD"]
    
    viewer_protocol_policy   = "redirect-to-https"                                      # 뷰어 프로토콜 정책
    compress                 = true                                                     # 자동으로 객체 압축
    default_ttl              = 2592000
    max_ttl                  = 31536000
    min_ttl                  = 2592000

    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"                            # Managed-CachingOptimized
    origin_request_policy_id = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"                   # Managed-CORS-S3Origin
    response_headers_policy_id = "5cc3b908-e619-4b99-88e5-2cf7f45965bd"                 # Managed-SimpleCORS
  }

  
  custom_error_response {                                                               # fallback 설정
    error_caching_min_ttl = 0
    error_code            = 403
    response_code         = 200
    response_page_path    = "/${local.s3_default_object}"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["KR"]
    }
  }
}

resource "aws_cloudfront_origin_access_control" "s3_origin" {
  name                              = "${local.s3_bucket_name}.s3.ap-northeast-2.amazonaws.com"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
