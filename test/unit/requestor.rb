require_relative '../_lib'

class RequestorTest < Critic::Unit::Test
  include Configatron::Integrations::Minitest

  def get_requestor_client
    client = mock()
    requestor = Gaps::Requestor.new(Gaps::DB::User.new)
    requestor.stubs(:get_client).returns(client)

    [requestor, client]
  end

  def fake_response
    fake_response = mock()
    fake_response.stubs(:data).returns("")

    fake_response
  end

  describe "handle Google::APIClient::ServerError (Backend Error)" do
    it "default to retry" do
      requestor, client = get_requestor_client

      client.stubs(:execute!).at_least(2).raises(Google::APIClient::ServerError, "Backend Error").then.returns(fake_response)
      requestor.send(:request, "", "", {uri:''})
    end

    it "does not retry if opt[:noretry]" do
      requestor, client = get_requestor_client

      client.stubs(:execute!).at_most(1).raises(Google::APIClient::ServerError, "Backend Error").then.returns(fake_response)

      assert_raises(Google::APIClient::ServerError) {
        requestor.send(:request, "", "", {uri:'', noretry: true})
      }
    end
  end
end