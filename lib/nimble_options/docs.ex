defmodule NimbleOptions.Docs do
  @moduledoc false

  @basic_types [
    :any,
    :keyword_list,
    :non_empty_keyword_list,
    :atom,
    :integer,
    :non_neg_integer,
    :pos_integer,
    :float,
    :mfa,
    :mod_arg,
    :string,
    :boolean,
    :timeout,
    :pid,
    :reference
  ]

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
    type = if type = get_type_str(schema[:type]), do: " (#{type})", else: ""
    doc = indent_doc("  * `#{inspect(key)}`#{type}#{description}\n\n", indent)

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
    if Keyword.has_key?(schema, :default),
      do: "The default value is `#{inspect(schema[:default])}`."
  end

  defp get_type_str(nil), do: nil
  defp get_type_str({:custom, _mod, _fun, _args}), do: nil
  defp get_type_str({:or, _values}), do: nil
  defp get_type_str({:fun, arity}), do: "function of arity #{arity}"
  defp get_type_str(:keyword_list), do: "keyword list"
  defp get_type_str(:non_empty_keyword_list), do: "non-empty keyword list"
  defp get_type_str({:keyword_list, _keys}), do: "keyword list"
  defp get_type_str({:non_empty_keyword_list, _keys}), do: "non-empty keyword list"
  defp get_type_str({:in, enum}), do: "member of `#{inspect(enum)}`"
  defp get_type_str(type) when type in @basic_types, do: Atom.to_string(type)

  defp get_type_str({:list, subtype}) do
    if subtype_str = get_type_str(subtype), do: "list of: #{subtype_str}"
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
