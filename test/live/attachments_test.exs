defmodule T3.Live.AttachmentsTest do
  use ExUnit.Case, async: false
  @moduletag :live
  @moduletag skip:
               Enum.any?(
                 ~w(T3_LIVE_HTTP_URL T3_LIVE_RPC_URL T3_LIVE_ENVIRONMENT_TOKEN T3_LIVE_DISPOSABLE_UPLOADS),
                 &is_nil(System.get_env(&1))
               )

  for {type, name, mime, bytes} <- [
        {"file", "sdk-validation.txt", "text/plain", "T3 SDK disposable live validation\n"},
        {"image", "sdk-validation.png", "image/png",
         Base.decode64!(
           "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a5X8AAAAASUVORK5CYII="
         )}
      ] do
    @type_name type
    @file_name name
    @mime mime
    @bytes bytes
    test "#{type} upload, exact download and deletion" do
      token = System.fetch_env!("T3_LIVE_ENVIRONMENT_TOKEN")
      http = T3.HTTP.new(base_url: System.fetch_env!("T3_LIVE_HTTP_URL"), token: token)

      {:ok, rpc} =
        T3.RPC.start_link(url: System.fetch_env!("T3_LIVE_RPC_URL"), token: token)

      try do
        assert {:ok, upload} =
                 T3.RPC.call(rpc, "attachments.createUploadUrl", %{
                   "type" => @type_name,
                   "name" => @file_name,
                   "mimeType" => @mime,
                   "sizeBytes" => byte_size(@bytes)
                 })

        try do
          assert {:ok, %T3.HTTP.Response{status: 204}} =
                   T3.HTTP.Media.upload(http, upload["relativeUrl"], @bytes,
                     headers: [{"content-type", @mime}]
                   )

          assert {:ok, asset} =
                   T3.RPC.call(rpc, "assets.createUrl", %{
                     "resource" => %{
                       "_tag" => "attachment",
                       "attachmentId" => upload["attachmentId"],
                       "fileName" => @file_name,
                       "mimeType" => @mime
                     }
                   })

          assert {:ok, response} =
                   T3.HTTP.request(http, :get, asset["relativeUrl"], decode: :binary)

          assert response.body == @bytes
        after
          assert {:ok, _} =
                   T3.RPC.call(rpc, "attachments.delete", %{
                     "attachmentId" => upload["attachmentId"]
                   })
        end
      after
        T3.RPC.close(rpc)
      end
    end
  end
end
