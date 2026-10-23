# The example needs cluster_arn, vpc_id and subnet_ids. The nightly workflow exports the repository
# variables TF_VAR_cluster_arn, TF_VAR_vpc_id and TF_VAR_subnet_ids (a JSON list string) into the job environment.
# Run only by the nightly integration workflow, against real cloud credentials.
run "apply_minimal" {
  command = apply

  module {
    source = "./examples/minimal"
  }
}
