defmodule NimbleOptions.Docs do
  @moduledoc false

  def generate(schema, options) when is_list(schema) and is_list(options) do
    nest_level = Keyword.get(options, :nest_level, 0)
    {docs, sections, _level} = build_docs(schema, {[], [], nest_level})
    to_string([Enum.reverse(docs), Enum.reverse(sections)])
  end

  # If the schema is a function, we want to not show anything (it's a recursive
  # function) and "back up" one level since when we got here we already
  # increased the level by one.
  defp build_docs(fun, {docs, sections, level}) when is_function(fun) do
    {docs, sections, level - 1}
  end

  defp build_docs(schema, {docs, sections, level} = acc) do
    if schema[:*] do
      build_docs(schema[:*][:keys], acc)
    else
      Enum.reduce(schema || [], {docs, sections, level}, &maybe_option_doc/2)
    end
  end

  defp build_docs_with_subsection(subsection, schema, {docs, sections, level}) do
    subsection = String.trim_trailing(subsection, "\n") <> "\n\n"

    {item_docs, sections, _level} = build_docs(schema, {[], sections, 0})
    item_section = [subsection | Enum.reverse(item_docs)]

    {docs, [item_section | sections], level}
  end

  defp maybe_option_doc({key, schema}, acc) do
    if schema[:doc] == false do
      acc
    else
      option_doc({key, schema}, acc)
    end
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
    doc = indent_doc("  * `#{inspect(key)}`#{description}\n\n", indent)

    docs = [doc | docs]

    cond do
      schema[:keys] && schema[:subsection] ->
        build_docs_with_subsection(schema[:subsection], schema[:keys], {docs, sections, level})

      schema[:keys] ->
        {docs, sections, _level} = build_docs(schema[:keys], {docs, sections, level + 1})
        {docs, sections, level}

      true ->
        {docs, sections, level}
    end
  end

  defp get_doc_str(schema) do
    schema[:doc] && String.trim(schema[:doc])
  end

  defp get_required_str(schema) do
    if schema[:required], do: "Required."
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
