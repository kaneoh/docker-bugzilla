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
ENV CPANM cpanm --quiet --notest --skip-satisfied

# Software installation
RUN yum -y -q update && yum clean all
RUN yum -y install git fcgi-perl mysql gcc perl-core perl-App-cpanminus perl-CPAN mod_perl-devel && \
    yum clean all

# Clone the code repo
RUN git clone $GITHUB_BASE_GIT -b $GITHUB_BASE_BRANCH $BUGZILLA_HOME

# Install Perl dependencies
# Some modules are explicitly installed due to strange dependency issues
RUN cd $BUGZILLA_HOME \
    && $CPANM Apache2::SizeLimit \
    && $CPANM Cache::Memcached \
    && $CPANM DBD::mysql \
    && $CPANM Email::Sender \
    && $CPANM File::Copy::Recursive \
    && $CPANM File::Which \
    && $CPANM HTML::FormatText \
    && $CPANM HTML::FormatText::WithLinks \
    && $CPANM HTML::TreeBuilder \
    && $CPANM Locale::Language \
    && $CPANM Net::SMTP::SSL \
    && $CPANM Pod::Checker \
    && $CPANM Pod::Coverage \
    && $CPANM Software::License \
    && $CPANM Test::WWW::Selenium \
    && $CPANM Text::Markdown \
    && $CPANM JSON::XS \
    && $CPANM Pod::Coverage \
    && $CPANM --installdeps --with-recommends . \
    && chown -R apache:apache $BUGZILLA_HOME

ADD scripts /scripts
RUN chmod +x /scripts/*.sh && \
    touch /first_run

# Expose our web root and log directories log.
VOLUME ["/data", "/var/log"]

# Expose the port
EXPOSE 80 443

# Kicking in
CMD ["/scripts/start.sh"]

