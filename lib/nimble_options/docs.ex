defmodule NimbleOptions.Docs do
  @moduledoc false

  def generate(schema) do
    {docs, sections, _level} = build_docs(schema, {[], [], 0})

    doc = if schema[:doc], do: "#{schema[:doc]}\n\n", else: ""
    to_string(["## Options\n\n#{doc}", Enum.reverse(docs), Enum.reverse(sections)])
  end

  defp build_docs(schema, {docs, sections, level} = acc) do
    cond do
      schema[:keys][:*] ->
        build_docs(schema[:keys][:*], acc)

      schema[:keys] ->
        Enum.reduce(schema[:keys], {docs, sections, level + 1}, &option_doc/2)

      true ->
        acc
    end
  end

  defp build_docs_with_subsection(schema, {docs, sections, level}) do
    subsection =
      case schema[:subsection] do
        nil ->
          ""

        text ->
          String.trim_trailing(text, "\n") <> "\n\n"
      end

    {item_docs, sections, _level} = build_docs(schema, {[], sections, 0})
    item_section = [subsection | Enum.reverse(item_docs)]

    {docs, [item_section | sections], level}
  end

  defp option_doc({key, {fun, schema}}, acc) when is_function(fun) do
    option_doc({key, schema}, acc)
  end

  defp option_doc({key, schema}, {docs, sections, level}) do
    description =
      [get_required_str(schema), get_doc_str(schema), get_default_str(schema)]
      |> Enum.reject(&is_nil/1)
      |> case do
        [] -> ""
        parts -> " - " <> Enum.join(parts, " ")
      end

    indent = String.duplicate("  ", level)
    doc = indent_doc("* `#{inspect(key)}`#{description}\n\n", indent)
    acc = {[doc | docs], sections, level}

    if schema[:subsection] do
      build_docs_with_subsection(schema, acc)
    else
      build_docs(schema, acc)
    end
  end

  defp get_doc_str(schema) do
    schema[:doc] && String.trim(schema[:doc])
  end

  defp get_required_str(schema) do
    schema[:required] && "Required."
  end

  defp get_default_str(schema) do
    if Keyword.has_key?(schema, :default) do
      "The default value is `#{inspect(schema[:default])}`."
    end
  end

  defp indent_doc(text, indent) do
    text
    |> String.split("\n")
    |> Enum.map_join("\n", fn
      "" -> ""
      str -> "#{indent}#{str}"
    end)
  end
end
