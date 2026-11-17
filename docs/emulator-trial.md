# Trial: can AWS Emulator run this repo's integration tests?

- **Date:** 2026-11-17
- **Status:** trial finished. Nothing in the build was switched or changed.
- **Question:** this repo tests its Terraform against Moto, a community emulator of the AWS APIs
  ([ADR 0001](adr/0001-test-offline-with-moto.md)). On 2026-11-11 AWS announced its own, AWS Emulator.
  Should the repo use it instead of Moto, or beside it?

## Short answer

Should the daily build use the emulator? **Not as the check that decides pass or fail, and not instead of
Moto.** Of the 7 folders with integration tests (six modules and `envs/dev`), 4 pass on the emulator and 3 fail: two
because the emulator has not implemented one EC2 operation the VPC module needs (`ReplaceRoute`, HTTP
501), one because a test hard-codes Moto's account ID. The emulator is still worth running **beside** Moto
as an advisory second opinion, because where both work it is the more faithful of the two: it kept S3
bucket tags that Moto silently dropped, it accepts two things the modules had to avoid or leave untested
because of Moto, and it refused an IAM trust policy that AWS refuses and Moto accepts. It costs about
three more minutes per full run and a 164 to 199 MB download. It is six days old and published ten
releases on the day of this trial, so it should stay advisory, pinned to one version, until it has run
green for a few weeks.

## What was compared

| | Moto | AWS Emulator |
| --- | --- | --- |
| Version | 5.2.5 (pinned in `.tool-versions`) | 1.0.492, commit `c77c1dc`, released 2026-11-17 |
| Who makes it | Community project, Apache-2.0 | AWS, CC0-1.0. No pull requests accepted: issues only |
| How it runs here | Python process started by `scripts/check.sh` | Docker container (macOS has no native build) |
| Endpoint | `http://127.0.0.1:5000` | `https://127.0.0.1:9297`, self-signed certificate made at each start |
| Credentials | Any (the tests use `test`/`test`) | Its own key pair made at each start, or anything with `--auth off` |
| Account ID it answers as | `123456789012` | `000000000000` |
| Clean state between modules | `POST /moto-api/reset` | No reset route: restart it |
| Telemetry | None | On by default. Off in every run here (`--telemetry off`) |

Same on both sides: Terraform 1.17.1, AWS provider 6.72.0, a MacBook Pro (M4 Max, macOS 27.2.1, Docker
Desktop 29.9.3), one server at a time, a fresh server for each module.

**How the tests reached the emulator.** The integration tests hard-code Moto's URL and fake keys in a
`provider` block, and Terraform gives a test file's own values priority over `-var` and `TF_VAR_...`
(measured, see [Options for pointing tests at either server](#options-for-pointing-tests-at-either-server)).
The emulator also only speaks HTTPS, so it cannot simply take Moto's place on port 5000. So
[`run.sh`](emulator-trial/run.sh) copies `modules/` and `envs/` to a folder outside the repo and tests the
copies. The committed tests are untouched. For the emulator the copies get two mechanical edits:

1. `http://127.0.0.1:5000` becomes `https://127.0.0.1:9297`.
2. The `access_key` and `secret_key` lines are removed, so the provider reads the emulator's own keys
   from the credentials file the emulator writes. `AWS_CA_BUNDLE` points at its certificate.

A second run kept the fake keys and started the emulator with `--auth off`: same results.

`modules/labels` has no integration test (it creates no AWS resources), so 7 folders were tested. Only
the integration tests were run; unit tests use a mock provider and never reach either server.

## Results per module

Identical in four passes on each server (one first pass, then three timed ones).

| Folder | Runs | Moto | AWS Emulator | First failing call on the emulator |
| --- | --- | --- | --- | --- |
| `modules/github-oidc` | 1 | pass | pass | |
| `modules/kms` | 1 | pass | pass | |
| `modules/state-backend` | 1 | pass | **fail** | No API call fails. The assertion `output.bucket_name == "platform-dev-tfstate-123456789012-us-east-1"` gets `...-000000000000-...` |
| `modules/vpc` | 4 | pass | **fail** (2 pass, 1 fail, 1 skipped) | `EC2 ReplaceRoute`: HTTP 501, `NotImplemented: operation ReplaceRoute is scaffolded but not implemented in this emulator` |
| `modules/vpc-endpoints` | 2 | pass | pass | |
| `modules/vpc-flow-logs` | 2 | pass | pass | |
| `envs/dev` | 2 | pass | **fail** (1 pass, 1 fail) | `EC2 ReplaceRoute`, same 501 |
| **Total** | 13 | 7 of 7 folders | 4 of 7 folders | |

Terraform called **104 different API operations** across the seven folders (about 1,300 calls on each
server). The emulator answered 103 of them; `ReplaceRoute` is the only 501. Full lists:
[Moto](emulator-trial/results/api-calls-moto.txt), [emulator](emulator-trial/results/api-calls-emulator.txt).

### The three failures

**`ReplaceRoute` (501 not implemented, 2 folders).** A route sends traffic for a destination to a target.
When a test switches from one NAT gateway per availability zone to a single shared one, Terraform changes
the target of the existing `0.0.0.0/0` routes in place, and the EC2 operation for that is `ReplaceRoute`.
The emulator returns 501 for every operation it has not implemented yet, and a test that hits one fails at
once. This one is in the emulator's own list of open gaps since 2026-11-04
(`issues/things-that-do-not-work/20261104T062058Z-ec2-replaceroute-stub.md`, one of 128 EC2 operations
listed there as unimplemented stubs). With that one run deleted from the copy, the other three `vpc` runs
pass, including the one the failure had caused to be skipped.

**Account ID (a test assumption, 1 folder).** The emulator did nothing wrong. The test expects Moto's
account ID in the bucket name. With `123456789012` replaced by `000000000000` in the copy, `state-backend`
passes. Building the expected name from `data.aws_caller_identity` would make the test pass on both.

**No Terraform provider problem** showed up: HTTPS with the emulator's certificate, its generated keys and
SigV4 signature checks all worked with provider 6.72.0 through `AWS_CA_BUNDLE` and
`AWS_SHARED_CREDENTIALS_FILE`.

## Timing

Medians of three timed passes. Start-up is from launching the server to its health route answering; for
the emulator that includes starting the container.

| Folder | Moto test time | Emulator test time |
| --- | --- | --- |
| `modules/github-oidc` | 1.1 s | 0.9 s |
| `modules/kms` | 13.2 s | 13.1 s |
| `modules/state-backend` | 57.5 s | 57.3 s (fails) |
| `modules/vpc` | 42.8 s | 42.2 s (fails) |
| `modules/vpc-endpoints` | 17.3 s | 16.9 s |
| `modules/vpc-flow-logs` | 14.1 s | 13.6 s |
| `envs/dev` | 34.2 s | 34.0 s (fails) |
| **All seven** | **180.2 s** | **178.0 s** |
| **Start-up, median of 21 starts** | **0.26 s** (0.26 to 0.44) | **0.34 s** (0.22 to 0.37) |

The two are the same to within a second per folder, and run-to-run spread was under 0.3 s. The reason is
that neither server is what the time is spent on: in the `vpc` folder Terraform waited 3.1 s in total for
Moto's answers and 0.33 s for the emulator's, out of about 42 s. The rest is waiting built into the AWS
provider (it pauses and re-reads after creating things such as KMS keys, S3 settings and NAT gateways,
because real AWS takes time to settle). So the emulator answers each request several times faster, and it
makes no difference to how long the tests take.

Other measured costs of the emulator:

- **Download:** the package for Apple silicon Linux is 171,268,001 bytes (163 MiB). The x86-64 Debian
  package a GitHub runner would use is 198,943,224 bytes. Moto is a `pip install`.
- **On disk:** the Docker image is 1.84 GB (the installed emulator is 964 MB). Build time after the
  download: 29 s.
- **Memory:** 187 to 212 MiB per container at the end of a module's tests, against the 2 GiB limit AWS's
  documented command sets. One reading of 945 MiB, on the very first container start, did not repeat.

## Where the two differ in what they tell you

### State read back after apply

`terraform test -verbose` prints the state after each run. [`state-diff.py`](emulator-trial/state-diff.py)
compares the two servers' output for the same run after replacing IDs, account numbers and addresses with
placeholders ([full output](emulator-trial/results/state-diff.txt)). Security groups, route tables,
internet gateways, IAM roles and flow logs read back the same. The differences that matter:

| Resource | Moto | AWS Emulator | What real AWS does |
| --- | --- | --- | --- |
| S3 bucket tags | **Dropped.** The provider sends the tags inside `CreateBucket`; Moto ignores them, `GetBucketTagging` answers 404, state has `tags = {}` | Kept: all four labels read back | Keeps them |
| S3 default encryption on a new bucket | None (`GetBucketEncryption` 404) | `AES256` | `AES256` on every new bucket since 2023 |
| S3 `PutBucketPolicy` status | 200 | 204 | 204 |
| KMS key `rotation_period_in_days` with rotation on | `0` | `365` | `365` is the default period |
| VPC `dhcp_options_id` | `"default"` | `dopt-...` | `dopt-...` (see `docs/live/2026-11-17-vpc/evidence/vpc.json`) |
| NAT gateway | No network interface, private IP, public IP or association ID | All present | All present |
| Elastic IP `public_ipv4_pool`, `network_border_group` | `null` | `amazon`, `us-east-1` | As the emulator |
| Interface endpoint DNS names | One invented name per endpoint | Regional, per-zone and private names, as the console shows them | As the emulator |
| Log group `log_group_class` | `null` | `STANDARD` | `STANDARD` is the default |
| Deleted VPC endpoint, read again | 200, still listed, with state `deleted` | 400 `InvalidVpcEndpointId.NotFound` | 400 `InvalidVpcEndpointId.NotFound` once the deletion has finished |
| Availability zones in `us-east-1` | 6 (`a` to `f`) | 3 (`a` to `c`) | 6 |

The first row is the one with a consequence today. `modules/state-backend` tags its bucket, the Moto test
passes, and the tags are not there. No test asserts them, so nothing noticed. An assertion on the
bucket's tags would be impossible to pass on Moto 5.2.5 and passes on the emulator.

The last row goes the other way: a test with more than three availability zones would behave differently
on the emulator than on AWS.

"What real AWS does" comes from AWS's documentation and, for one row, from this repo's own drill evidence.
It was not measured in this trial, which used no AWS account.

### The Moto gaps the module READMEs record

[`probes.sh`](emulator-trial/probes.sh) applies small throwaway configurations to both servers
([results](emulator-trial/results/probes.tsv)).

| Gap recorded in the repo | Moto | AWS Emulator |
| --- | --- | --- |
| S3 lifecycle rule with `newer_noncurrent_versions` ("always keep the last N versions"). `modules/state-backend` dropped the setting because of this | Fails after 183 s: Moto does not return the setting, the provider waits 3 minutes for it and gives up | Applies in 57.5 s and reads back `newer_noncurrent_versions = 3` |
| Attaching an AWS-managed policy such as `ReadOnlyAccess`. `modules/github-oidc` covers attachment with unit tests only | Fails: 404 `NoSuchEntity` | Applies |
| Enforcing policies (the TLS-only bucket policy, KMS key policies, IAM trust policies) | Not enforced | Not enforced either. AWS's documentation says not to use the emulator to test security |
| Delivering flow log records, resolving private DNS | No | Not tested here |

### Requests that real AWS refuses

| Request | Real AWS | Moto | AWS Emulator |
| --- | --- | --- | --- |
| IAM role whose trust policy names a role that does not exist | Refuses: `MalformedPolicyDocument: Invalid principal in policy` | **Accepts** | Refuses with that same error |
| Subnet whose CIDR is outside the VPC's | Refuses: `InvalidSubnet.Range` | Refuses, same code | Refuses, same code |
| NAT gateway with an Elastic IP allocation that does not exist | Refuses: `InvalidAllocationID.NotFound` | Refuses, same code | Refuses, same code |
| KMS key policy that names a role that does not exist | Refuses: `MalformedPolicyDocumentException` | Accepts | **Accepts** |
| Bucket policy whose `Resource` is a different bucket | Refuses: `MalformedPolicy` | Accepts | **Accepts** |

The "Real AWS" column is AWS's documented behaviour as I know it, not something this trial measured.

So the emulator caught one mistake that Moto let through, and neither catches the two policy mistakes at
the bottom. Those two still need the live drill.

A side effect worth knowing: the refused IAM role took 137 s to fail on the emulator, because the
provider retries that error for two minutes (on real AWS a new principal can take a moment to become
visible). A wrong principal in a module would make its test slow, then fail.

### What Moto does that the emulator does not

- `ReplaceRoute`, and with it two of this repo's seven folders.
- A reset route, so one server can serve every module. The emulator has to be restarted (0.34 s here).
- Plain HTTP on a fixed port with any credentials, which is why the committed tests can be so simple.
- A stable release rhythm. The emulator published 42 releases between 2026-11-07 and 2026-11-17, ten of
  them on the day of this trial, and AWS's versioning page says a patch release may change a response
  that no fidelity test covers yet.

## AWS's own fidelity scores

AWS publishes, with each release, how many of its "fidelity tests" the emulator passes. A fidelity test
replays a short workflow against real AWS and then against the emulator and compares every answer. For
release 1.0.492 (the build tested here), for the six services this repo's tests use:

| Service | Fidelity tests passed |
| --- | --- |
| KMS | 465 of 571 (81%) |
| S3 | 2,279 of 2,988 (76%) |
| CloudWatch Logs | 965 of 1,303 (74%) |
| IAM | 963 of 1,377 (70%) |
| STS | 201 of 294 (68%) |
| EC2 | 1,470 of 2,639 (56%) |
| All 356 services | 32,139 of 46,026 (70%) |

EC2 is the weakest of the six and is where this repo failed. These are AWS's numbers from
`scores.json.gz` on the release page; this trial did not re-run them. For the roadmap's next services the
emulator's own list of open issues has 44 files for ECR, 38 for EKS, 126 for DynamoDB and 246 for Lambda.
That is a count of file names, not a test: whether `modules/ecr` or `modules/eks` would apply was not
tried.

## What I could not determine

- **Whether the emulator's answers match real AWS for these modules.** No AWS account was used, by the
  repo's rules. Every "as AWS does" above rests on AWS documentation, on one file of drill evidence, or on
  AWS's published scores.
- **Whether the daily cloud routine can install it.** That VM is Linux, where the emulator is a native
  package, but `scripts/bootstrap.sh` shows its network blocks some hosts. Whether `downloads.aws.com` is
  reachable from it, and whether a 199 MB package can be installed there without root, was not tested.
- **Native Linux numbers.** Start-up time, memory and behaviour on GitHub's `ubuntu-24.04` runner were
  not measured. Everything here ran in Docker on a Mac.
- **Anything beyond creating, reading and deleting resources.** No test here puts an object in a bucket,
  encrypts with a key or sends a log line, so the emulator's data-plane behaviour is untested. AWS says
  that is where its fidelity is lowest.
- **Stability.** One version on one day. I did not test whether tomorrow's release gives the same results.
- **The 945 MiB memory reading** on the first container start. The 43 other readings were between 187
  and 212 MiB, and I did not find the cause.
- **`modules/labels`** and all unit tests: they never reach a server, so there was nothing to compare.

## Recommendation: run both, Moto stays the required check

1. **Keep Moto as the gate.** It runs every folder today and the emulator does not.
2. **Add the emulator as an advisory second pass** behind a flag in `scripts/check.sh`. It reports, and
   never fails the build. It earns the three extra minutes because it showed three real things in one
   afternoon: the dropped bucket tags, the lifecycle setting the state bucket gave up for Moto's sake, and
   the trust policy AWS would refuse.
3. **Start it in CI, not in the daily cloud run,** until someone has checked that the cloud VM can
   download and run it. Pin one version and raise it on purpose.
4. **Look again at switching** when `ReplaceRoute` is implemented and the pinned version has been green
   for a few weeks. Until then a switch would lose coverage of the NAT strategy, which is exactly the
   part of the network module with a cost decision behind it (ADR 0004).

### Proposed changes (none of these were made)

This pull request only adds this document and the trial tooling under `docs/emulator-trial/`. The files
below are for Rodrigo to change or approve, and several are on the protected list in `CLAUDE.md`.

**`scripts/check.sh`**: after the Moto loop, before tflint:

```bash
# Advisory second opinion: the same integration tests against AWS Emulator. Reports, never fails the
# build. Off unless EMULATOR=1. See docs/emulator-trial.md.
if [ "${EMULATOR:-0}" = 1 ]; then
  step "AWS Emulator (advisory)"
  scripts/emulator-check.sh "${dirs[@]}" || echo "emulator: differences found, see above (advisory)"
fi
```

**`scripts/emulator-check.sh`** (new): `docs/emulator-trial/run.sh` moved and extended to

- skip folders without `tests/integration.tftest.hcl` (the `live/` folders);
- use the native `aws-emulator` command when it is on `PATH` (Linux) and Docker otherwise (macOS);
- always pass `--telemetry off` and `--idle-timeout 600`, so a forgotten emulator stops by itself;
- compare results with a short list of known gaps, `scripts/emulator-known-gaps.tsv`, and print one of
  three things per folder: `pass`, `known gap` (expected failure), or `NEW FAILURE`. A folder on the list
  that now passes prints `now passes: remove it from the list`. Starting list: `modules/vpc` and
  `envs/dev` (`ReplaceRoute`).

**`modules/state-backend/tests/integration.tftest.hcl`**: build the expected bucket name from
`data.aws_caller_identity.current.account_id` instead of the literal `123456789012`. The test then passes
on both servers and `state-backend` never goes on the known-gaps list.

**`.tool-versions` and `scripts/bootstrap.sh`**: add `aws-emulator 1.0.492` and an install step that
downloads the versioned package from `downloads.aws.com`, verifies AWS's GPG signature (fingerprint
`98BC F336 A3BE 53B7 34E9 67C5 2E5B F49B D940 F624`, as the user guide gives it) and, on macOS, builds
the image from `docs/emulator-trial/Dockerfile`. `.tool-versions` is drill machinery, so this is a change
for Rodrigo to make by hand.

**`.github/workflows/ci.yml`**: a second job, `emulator`, with `continue-on-error: true`, that runs
`EMULATOR=1 scripts/check.sh` on `ubuntu-24.04`. It must not be a required check.

**`CLAUDE.md`**, under "Tests": "Integration tests must also be able to run on AWS Emulator: do not
hard-code the account ID, and note in the module README anything that passes on one server and not the
other."

**`.claude/daily-run.md`**: once the cloud VM question is answered, "run `EMULATOR=1 scripts/check.sh`;
an emulator failure never blocks the push; list any `NEW FAILURE` under 'Please look at'."

**`docs/adr/`**: a short ADR recording the decision, amending ADR 0001 ("Moto and, as an advisory check,
AWS Emulator").

**Follow-ups this trial opens**, each its own small change:

- `modules/state-backend` could take `newer_noncurrent_versions` back if the emulator run covers it. Moto
  still cannot, so the Moto test would have to leave that rule out.
- An assertion on the state bucket's tags, which only the emulator can pass.
- Reporting `ReplaceRoute` to the emulator's issue tracker (a thumbs-up on the existing gap, or a
  "Behavior differs from AWS" issue). That posts under Rodrigo's name, so it is his call.

### Options for pointing tests at either server

Measured with Terraform 1.17.1, for whoever writes `emulator-check.sh`:

| Option | Works? | Cost |
| --- | --- | --- |
| Test copies with the URL rewritten (what this trial did) | Yes | Tests stay as they are. The check tests a copy, not the file in the repo |
| `endpoints { ec2 = var.aws_endpoint }` with a default in the test's `variables` block, overridden by `-var` or `TF_VAR_aws_endpoint` | **No.** The test file's own value wins over both | |
| The same with no default in the test file | Yes, with the value quoted: `TF_VAR_aws_endpoint='"https://127.0.0.1:9297"'` | `terraform test` run by hand without the variable fails with "Reference to unavailable variable" |
| No `endpoints` block, `AWS_ENDPOINT_URL` in the environment | Yes | If the variable is ever missing, the provider calls real AWS. AWS's guide warns about exactly this |
| Emulator on port 5000 in Moto's place | No. It only serves HTTPS | |

The first option is the safest and is the one proposed.

## Reproduce

Needs Docker, GnuPG and the repo toolchain (`scripts/bootstrap.sh`). No AWS credentials. On macOS, port
5000 is also used by AirPlay Receiver; Moto still binds `127.0.0.1:5000` beside it.

Get the package for your processor and check AWS's signature (`aarch64` on Apple silicon, `x86_64`
otherwise):

```bash
mkdir -p /tmp/aws-emulator-image && cd /tmp/aws-emulator-image
curl -fsSLo aws-emulator-aarch64.rpm https://downloads.aws.com/aws-emulator/packages/aws-emulator/LTS/aws-emulator-1.0.492-1-aarch64.rpm
curl -fsSLo aws-emulator-aarch64.rpm.sig https://downloads.aws.com/aws-emulator/packages/aws-emulator/LTS/aws-emulator-1.0.492-1-aarch64.rpm.sig
curl -fsSLo aws-publishing.asc https://downloads.aws.com/keys/gpg/current.asc
gpg --import aws-publishing.asc && gpg --fingerprint ssm-publishing@amazon.com
gpg --verify aws-emulator-aarch64.rpm.sig aws-emulator-aarch64.rpm
```

The SHA-256 of the package used here was
`38e2069c656429eaa023fdc807a49c02a48acff77f090f068ccdc9fa0a7c4fe4`.

Build the image from the folder that holds the package, with `<repo>` replaced by the path of this
repository (on x86-64 add `--build-arg PACKAGE=aws-emulator-x86_64.rpm`):

```bash
docker build -t aws-emulator-trial -f <repo>/docs/emulator-trial/Dockerfile .
```

Then, from the repo root:

```bash
docs/emulator-trial/run.sh moto 1
```

```bash
docs/emulator-trial/run.sh emulator 1
```

Variants used above:

```bash
EMULATOR_AUTH=off docs/emulator-trial/run.sh emulator authoff
ALIGN_ACCOUNT=1 docs/emulator-trial/run.sh emulator align modules/state-backend
DROP_RUN=single_nat_shared_by_all_private_route_tables docs/emulator-trial/run.sh emulator droprun modules/vpc
TF_DEBUG=1 docs/emulator-trial/run.sh moto debug && TF_DEBUG=1 docs/emulator-trial/run.sh emulator debug
```

Results land in `$TMPDIR/emulator-trial/results/<server>/<pass>/` (`summary.tsv`, one test log and one
server log per folder). Then:

```bash
R=${TMPDIR:-/tmp}/emulator-trial/results
docs/emulator-trial/api-calls.py $R/emulator/debug/*.tf-debug.log
docs/emulator-trial/state-diff.py $R/moto/1/modules_kms.test.log $R/emulator/1/modules_kms.test.log
docs/emulator-trial/probes.sh moto && docs/emulator-trial/probes.sh emulator
```

The numbers in this document are in [`emulator-trial/results/`](emulator-trial/results/):
`passes.tsv` (every pass), `probes.tsv`, the two API call lists, `error-answers.txt` (every non-2xx answer
on each server) and `state-diff.txt`.

To remove everything afterwards: `docker image rm aws-emulator-trial` and delete
`$TMPDIR/emulator-trial`. The emulator wrote nothing to `~/.aws`: the runner mounts a folder of its own.

## Sources

- AWS Emulator user guide: <https://docs.aws.amazon.com/emulator/latest/userguide/what-is-service.html>
  (getting started with Docker, command reference, fidelity, versions, security, telemetry)
- Repository and releases: <https://github.com/aws/aws-emulator>
- Fidelity tests: the `aws-emulator-evaluation-suite` repository named in the user guide
