module Gaps::Filter
  include Chalk::Log

  def self.translate_to_gmail_britta_filters(id_based_filters)
    # Translate the group _id to an email address

    groups = {}
    Gaps::DB::Group.all(:_id => {:$in => id_based_filters.keys}).each do |grp|
      groups[grp._id] = grp
    end

    filters = {}
    id_based_filters.each do |group_id, filter|
      filters[groups[group_id].group_email] = filter
    end
    filters
  end

  def self.generate_filter_xml(user_emails, generic_lists, &block)
    create_filterset(user_emails, generic_lists, &block).generate
  end

  def self.upload_to_gmail(user_object)
    generic_lists = Gaps::Filter.translate_to_gmail_britta_filters(user_object.filters)
    filterset = create_filterset(user_object.all_emails, generic_lists)

    props = filterset.filters.map(&:generate_xml_properties)
    futures = props.map do |filter_text|
      Thread.future(Gaps::DB::Group.thread_pool) do
        retried = false
        begin
          user_object.requestor.create_filter(filter_text)
        rescue StandardError => e
          log.info('Error creating filter', e, filter_text: filter_text)
          next [filter_text, false] if retried

          retried = true
          sleep(Random.rand * 2 + 2)

          retry
        else
          [filter_text, true]
        end
      end
    end

    failures = futures.map(&:~).select {|_, success| !success}
    failures.map {|filter_text, _| filter_text}
  end

  private

  def self.create_filterset(user_emails, generic_lists, &block)
    # Problem: if you archive list:X, and don't archive list:Y, and
    # somebody sends an email to X and Y, it'll archive it
    #
    # Hack: mark all non-archived lists as user_emails so they get
    # added to the "unless_directed" part of archive logic.
    desired = generic_lists.
      select {|list, spec| spec['archive']}.
      map {|list, _| list}

    unarchived = user_emails + desired

    GmailBritta.filterset(me: unarchived) do
      generic_lists.each do |list, spec|
        f = filter {
          has ["list:#{list}"]
          label spec['label']
        }
        f.archive_unless_directed if spec['archive']
      end

      user_emails.each do |email|
        filter {
          has ["to:#{email}"]
          label "#{email.split('@')[0]}"
        }
      end

      block.call if block
    end
  end
end
