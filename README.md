#homeops
[![FOSSA Status](https://app.fossa.com/api/projects/git%2Bgithub.com%2Fdels78%2Fhomeops.svg?type=shield)](https://app.fossa.com/projects/git%2Bgithub.com%2Fdels78%2Fhomeops?ref=badge_shield)

This repository is my home playground!

GitOps/ArgoCD managed k3s cluster to host home applications!

Some pieces that are not gitops and are a pre-requisite to this:
- I have a little k3s cluster of 4 small used Zotac boxes that are all configured via another private repo with CoreOS (1 master and 3 agent k3s nodes)
- all of the ingresses are behind Cloudflare Zero Trust which requires either my home IP or my github authentication to view


## License
[![FOSSA Status](https://app.fossa.com/api/projects/git%2Bgithub.com%2Fdels78%2Fhomeops.svg?type=large)](https://app.fossa.com/projects/git%2Bgithub.com%2Fdels78%2Fhomeops?ref=badge_large)