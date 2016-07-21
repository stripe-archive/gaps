FROM phusion/passenger-ruby21:0.9.19
MAINTAINER Greg Brockman <gdb@stripe.com>
ENV PORT 3500
EXPOSE 3500
ADD Gemfile* /gaps/
RUN cd /gaps && bundle install --path vendor/bundle
ADD . /gaps
# If you're running a version of docker before .dockerignore
RUN rm -f /gaps/site.yaml*
RUN chown -R app: /gaps
USER app
ENV HOME /home/app
ENV RACK_ENV production
WORKDIR /gaps
CMD ["bin/hk-runner"]
