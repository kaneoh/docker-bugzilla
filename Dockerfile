FROM muzili/centos-nginx
MAINTAINER Zhiguang Li <muzili@gmail.com>

# Environment configuration
ENV container docker
ENV BUGS_DB_DRIVER mysql
ENV BUGS_DB_NAME bugs
ENV BUGS_DB_PASS bugs
ENV BUGS_DB_HOST localhost

ENV BUGZILLA_USER bugzilla
ENV BUGZILLA_HOME /home/bugzilla
ENV BUGZILLA_URL http://localhost/bugzilla

ENV GITHUB_BASE_GIT https://github.com/bugzilla/bugzilla
ENV GITHUB_BASE_BRANCH 5.0
ENV GITHUB_QA_GIT https://github.com/bugzilla/qa

ENV ADMIN_EMAIL admin@bugzilla.org
ENV ADMIN_PASS password
ENV TEST_SUITE sanity
ENV CPANM perl $BUGZILLA_HOME/install-module.pl

# Software installation
RUN yum -y -q update && yum clean all
RUN yum -y install memcached gcc-c++ gd-devel tar zip gzip bzip2 git fcgi-perl mariadb mariadb-devel mariadb-libs gcc perl-core perl-App-cpanminus perl-CPAN mod_perl-devel && \
    yum clean all

# Clone the code repo
RUN git clone $GITHUB_BASE_GIT -b $GITHUB_BASE_BRANCH $BUGZILLA_HOME

# Install Perl dependencies
# Some modules are explicitly installed due to strange dependency issues
RUN cd $BUGZILLA_HOME \
    && $CPANM --all
    && chown -R nginx:nginx $BUGZILLA_HOME

ADD scripts /scripts
RUN chmod +x /scripts/*.sh && \
    chmod +x /scripts/fastcgi-wrapper.pl && \
    touch /first_run

# Expose our web root and log directories log.
VOLUME ["/data", "/var/log"]

# Expose the port
EXPOSE 80 443

# Kicking in
CMD ["/scripts/start.sh"]

