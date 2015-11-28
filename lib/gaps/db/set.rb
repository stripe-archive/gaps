module Gaps::DB
  class Set < Base
    set_collection_name 'set'

    key :name, String
    key :description, String
    key :groups, Array

    key :deleted, Boolean, default: false

    def groups_
      group_docs = Group.find_each(_id: {:$in => self.groups}).sort_by(&:group_email)
    end
  end
end
