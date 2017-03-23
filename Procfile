web: bundle exec puma -C puma.rb
deb_s3_worker: FORK_PER_JOB=false TERM_CHILD=1 RESQUE_TERM_TIMEOUT=30 QUEUE="deb-s3" bundle exec rake resque:work
fpm_worker: FORK_PER_JOB=false TERM_CHILD=1 RESQUE_TERM_TIMEOUT=30 QUEUE="fpm" bundle exec rake resque:work
redis: sudo redis
