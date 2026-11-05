defmodule T3.HTTP.Multipart do
  @moduledoc """
  Multipart request bodies backed by the `multipart` package, including streamed files.

      multipart = T3.HTTP.multipart(%{"shareId" => share_id, "text" => "Look at this"}, [
        {"file", "/absolute/path/image.png"},
        {"file", "notes.txt", "in-memory bytes", "text/plain"}
      ])
      T3.HTTP.Guest.messages(http, query: %{"share" => share_id}, multipart: multipart)

  Files are tuples of `{field_name, local_path}` or
  `{field_name, filename, binary_content, content_type}`. Building a local-file
  part stats the file; sending streams it through Finch without buffering the
  complete file. Fields are an enumerable of string field-name/value pairs.
  """
  def build(fields, files \\ []) do
    multipart =
      Enum.reduce(fields, Multipart.new(), fn {name, value}, acc ->
        Multipart.add_part(acc, Multipart.Part.text_field(to_string(value), to_string(name)))
      end)

    Enum.reduce(files, multipart, fn
      {name, path}, acc when is_binary(path) ->
        Multipart.add_part(acc, Multipart.Part.file_field(path, to_string(name)))

      {name, filename, content, content_type}, acc when is_binary(content) ->
        part =
          Multipart.Part.file_content_field(filename, content, to_string(name), [],
            content_type: content_type
          )

        Multipart.add_part(acc, part)
    end)
  end
end
