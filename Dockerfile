FROM phusion/passenger-ruby21
MAINTAINER Greg Brockman <gdb@stripe.com>
ADD . /gaps
# If you're running a version of docker before .dockerignore
RUN rm -f /gaps/site.yaml*
RUN chown -R app: /gaps
USER app
ENV HOME /home/app
RUN cd /gaps && bundle install --path vendor/bundle
WORKDIR /gaps
CMD ["bin/gaps_server.rb"]
