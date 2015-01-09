require_relative '../_lib'

class RequestorTest < Critic::Unit::Test
  include Configatron::Integrations::Minitest

  class FakeGoogleAPIClient
    attr :execute_count

    def initialize
      @execute_count = 0
    end

    def execute!(fake_opts)
      @execute_count += 1
      raise Google::APIClient::ServerError.new("Backend Error")
    end
  end

  class FakeResponse
    def data
      ""
    end
  end

  def get_requestor_client
    requestor = Gaps::Requestor.new(Gaps::DB::User.new)
    client = FakeGoogleAPIClient.new
    requestor.stubs(:get_client).returns(client)
    requestor.stubs(:sleep)

    [requestor, client]
  end

  describe "handle Google::APIClient::ServerError (Backend Error)" do
    it "default to retry" do
      requestor, client = get_requestor_client
      assert_raises(Google::APIClient::ServerError) {
        requestor.send(:request, "", "", {uri:''})
      }
      assert client.execute_count > 2
    end

    it "does not retry if opt[:noretry]" do
      requestor, client = get_requestor_client
      assert_raises(Google::APIClient::ServerError) {
        requestor.send(:request, "", "", {uri:'', noretry: true})
      }
      assert_equal 1, client.execute_count
    end
  end
end
