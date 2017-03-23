# Ekiden 駅伝

ekiden is an deb package relay app, used to centralized distributed access to a private apt repo

# Workflow

circleci> HTTP POST => ekiden.devstack/repo-sync-request APP URL_TO_DEB_FROM_CIRCLE_ARTIFACTS_CDN
ekiden> ON POST to create repo-sync-request => create backend single process queue

    curl -XPOST -F deb_url="http://www.lipsum.com/public-server/cdn/build/output.deb" -s -v http://localhost:9292/packages/your-application-and-version-1.2.0.deb
