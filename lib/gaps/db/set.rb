module Gaps::DB
  class Set < Base
    set_collection_name 'set'

    key :name, String
    key :description, String
    key :groups, Array

    key :deleted, Boolean, default: false

    def groups_
      Group.find_each(_id: {:$in => self.groups}).sort_by(&:group_email)
    end

    def notify_update(old_groups)
      added_groups = self.groups - old_groups
      removed_groups = old_groups - self.groups
      changed_groups = added_groups + removed_groups
      return if changed_groups.empty?

      added_group_docs, removed_group_docs =
        Group.find_each(_id: {:$in => changed_groups}).partition {|group| added_groups.include?(group._id)}

      subject = "[gaps] Update to set: #{self.name}"
      body = "A set you've previously added has been updated.\n\n"

      unless added_group_docs.empty?
        body += "The following groups were added:\n"
        added_group_docs.each do |group|
          body += "  #{group.group_email}\n"
        end
        body += "You can subscribe to all of them at #{configatron.gaps_url}/sets\n\n"
      end

      unless removed_group_docs.empty?
        body += "The following groups were removed:\n"
        removed_group_docs.each do |group|
          body += "  #{group.group_email}: #{configatron.gaps_url}/subs#lst-#{group.group_email}\n"
        end
      end

      Gaps::DB::User.find_each(sets: {:$in => [self._id]}) do |user|
        Gaps::Email.send_email(
          :to => user.email,
          :from => configatron.notify.from,
          :subject => subject,
          :body => body
        )
      end
    end
  end
end
