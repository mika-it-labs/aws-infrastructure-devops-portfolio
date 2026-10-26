resource "aws_iam_role" "ec2" {
  name = "${var.name_prefix}-ec2"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = { Name = "${var.name_prefix}-ec2" }
}
resource "aws_iam_role_policy_attachment" "ec2" {
  for_each   = toset(["AmazonSSMManagedInstanceCore", "CloudWatchAgentServerPolicy"])
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/${each.key}"
}
resource "aws_iam_instance_profile" "ec2" {
  name = aws_iam_role.ec2.name
  role = aws_iam_role.ec2.name
  tags = { Name = "${var.name_prefix}-ec2" }
}
