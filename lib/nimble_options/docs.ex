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
    type_str = if type_str = get_type_str(schema), do: " #{type_str}"

    description =
      [
        get_required_str(schema),
        get_doc_str(schema),
        get_default_str(schema)
      ]
      |> Enum.reject(&is_nil/1)
      |> case do
        [] -> ""
        parts -> " - " <> Enum.join(parts, " ")
      end

    indent = String.duplicate("  ", level)
    doc = indent_doc("  * `#{inspect(key)}`#{type_str}#{description}\n\n", indent)

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

  defp get_type_str(schema) do
    if str = get_raw_type_str(schema[:type]) do
      "(#{str})"
    end
  end

  defp get_raw_type_str(nil), do: nil
  defp get_raw_type_str({:custom, _mod, _fun, _args}), do: nil
  defp get_raw_type_str(:mfa), do: "3-element tuple of `t:module/0`, `t:atom/0`, and `[term()]`"
  defp get_raw_type_str(:mod_arg), do: "2-element tuple of `t:module/0` and `[term()]`"
  defp get_raw_type_str({:or, _values}), do: nil
  defp get_raw_type_str({:fun, arity}), do: "function of arity #{arity}"
  defp get_raw_type_str({:in, enum}), do: "member of `#{inspect(enum)}`"
  defp get_raw_type_str(:any), do: "`t:term/0`"
  defp get_raw_type_str(:reference), do: "`t:reference/0`"
  defp get_raw_type_str(:pid), do: "`t:pid/0`"
  defp get_raw_type_str(:timeout), do: "`t:timeout/0`"
  defp get_raw_type_str(:boolean), do: "`t:boolean/0`"
  defp get_raw_type_str(:atom), do: "`t:atom/0`"
  defp get_raw_type_str(:integer), do: "`t:integer/0`"
  defp get_raw_type_str(:non_neg_integer), do: "`t:non_neg_integer/0`"
  defp get_raw_type_str(:pos_integer), do: "`t:pos_integer/0`"
  defp get_raw_type_str(:float), do: "`t:float/0`"
  defp get_raw_type_str(:string), do: "`t:String.t/0`"
  defp get_raw_type_str(:keyword_list), do: "`t:keyword/0`"
  defp get_raw_type_str(:non_empty_keyword_list), do: "non-empty `t:keyword/0`"
  defp get_raw_type_str({:keyword_list, _keys}), do: "`t:keyword/0`"
  defp get_raw_type_str({:non_empty_keyword_list, _keys}), do: "non-empty `t:keyword/0`"

  defp get_raw_type_str({:list, subtype}) do
    if subtype_str = get_raw_type_str(subtype), do: "list of #{subtype_str}"
  end

  defp indent_doc(text, indent) do
    text
    |> String.split(["\r\n", "\n"])
    |> Enum.map_join("\n", fn
      "" -> ""
      str -> "#{indent}#{str}"
    end)
  end

  def schema_to_spec(schema) do
    schema
    |> Enum.map(fn {key, opt_schema} ->
      typespec = type_to_spec(opt_schema[:type])
      quote do: {unquote(key), unquote(typespec)}
    end)
    |> unionize_quoted()
  end

  defp type_to_spec(type) do
    case type do
      :any -> quote(do: term())
      :integer -> quote(do: integer())
      :non_neg_integer -> quote(do: non_neg_integer())
      :pos_integer -> quote(do: pos_integer())
      :atom -> quote(do: atom())
      :float -> quote(do: float())
      :boolean -> quote(do: boolean())
      :pid -> quote(do: pid())
      :reference -> quote(do: reference())
      :timeout -> quote(do: timeout())
      :string -> quote(do: binary())
      :mfa -> quote(do: {module(), atom(), [term()]})
      :mod_arg -> quote(do: {module(), [term()]})
      :keyword_list -> quote(do: keyword())
      {:keyword_list, _keys} -> quote(do: keyword())
      :non_empty_keyword_list -> quote(do: keyword())
      {:non_empty_keyword_list, _keys} -> quote(do: keyword())
      {:fun, arity} -> function_spec(arity)
      {:in, _choices} -> quote(do: term())
      {:custom, _mod, _fun, _args} -> quote(do: term())
      {:list, subtype} -> quote(do: [unquote(type_to_spec(subtype))])
      {:or, subtypes} -> subtypes |> Enum.map(&type_to_spec/1) |> unionize_quoted()
    end
  end

  defp function_spec(arity) do
    args = List.duplicate(quote(do: term()), arity)

    quote do
      unquote_splicing(args) -> term()
    end
  end

  defp unionize_quoted(specs) do
    specs
    |> Enum.reverse()
    |> Enum.reduce(&quote(do: unquote(&1) | unquote(&2)))
  end
end
