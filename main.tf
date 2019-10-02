variable "name" {
  description = "the name of the lambda"
  type        = "string"
}

variable "handler_name" {
  description = "the function (and handler) name"
  type        = "string"
  default     = "handler"
}

variable "source_name" {
  description = "the name of the lambda source file"
  type        = "string"
  default     = "index.js"
}

variable "working_dir" {
  description = "the working directory where the source javascript resides"
  type        = "string"
}

variable "policy_json" {
  description = "additional policy json to be attached to the lambda"
  type        = "string"
}

variable "reserved_concurrent_executions" {
  description = "the reserved concurrent connections for the lambda"
  type        = "string"
  default     = "1"
}

variable "timeout" {
  description = "the timeout to configure with the lambda"
  type        = "string"
  default     = "5"
}

variable "memory_size" {
  description = "the memory size of the lambda"
  type        = "string"
  default     = "128"
}

// package the node modules
resource "null_resource" "package" {
  // make it run every time
  triggers = {
    build_number = timestamp()
  }

  provisioner "local-exec" {
    working_dir = var.working_dir
    command     = "parcel build ./${var.source_name} --target node --global ${var.handler_name} --bundle-node-modules --no-source-maps --no-minify --out-dir . --out-file ${var.name}.js"
  }
}

// archive the lambda
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${var.working_dir}/${var.name}.js"
  output_path = "${var.working_dir}/${var.name}.zip"
  depends_on  = ["null_resource.package"]
}

// create the log group
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.name}"
  retention_in_days = 14
}

// the assumed policies
data "aws_iam_policy_document" "assume" {
  policy_id = "${var.name}-assume"

  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type = "Service"

      identifiers = [
        "lambda.amazonaws.com",
      ]
    }
  }
}

// create a role for the lambda
resource "aws_iam_role" "lambda" {
  name               = var.name
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

// create the policy as passed in
resource "aws_iam_policy" "lambda" {
  name   = var.name
  policy = var.policy_json
}

// attach the policy to the role
resource "aws_iam_role_policy_attachment" "lambda" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda.arn
}

// create policy document for base access
data "aws_iam_policy_document" "base" {
  policy_id = "${var.name}-base"

  // to store logs
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    effect = "Allow"

    resources = [
      "arn:aws:logs:*:*:*",
    ]
  }
}

// create the base policy
resource "aws_iam_policy" "base" {
  name   = "${var.name}-base"
  policy = data.aws_iam_policy_document.base.json
}

// attach the base policy to the role
resource "aws_iam_role_policy_attachment" "base" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.base.arn
}

// create the lambda
resource "aws_lambda_function" "lambda" {
  function_name                  = var.name
  filename                       = data.archive_file.lambda.output_path
  role                           = aws_iam_role.lambda.arn
  handler                        = "${var.name}.${var.handler_name}"
  source_code_hash               = data.archive_file.lambda.output_base64sha256
  runtime                        = "nodejs10.x"
  reserved_concurrent_executions = var.reserved_concurrent_executions
  timeout                        = var.timeout
  memory_size                    = var.memory_size
}

// output the lambda arn
output "arn" {
  value = aws_lambda_function.lambda.arn
}

// output the lambda function name
output "function_name" {
  value = aws_lambda_function.lambda.function_name
}

