class Gaps::DB::Base
  class DBError < StandardError; end
  class UniqueKeyViolation < DBError; end

  include Chalk::Log

  include MongoMapper::Document
  safe
  timestamps!

  key :_id, String, default: ->{'model_' + Gaps::Third::StringUtils.random }

  def display_errors
    errors.map do |attribute, error|
      error
    end.join(', ')
  end

  def to_json(state=nil)
    JSON.unsafe_generate([self.to_s])[1..-1]
  end
end
