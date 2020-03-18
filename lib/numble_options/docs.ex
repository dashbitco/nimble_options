defmodule NimbleOptions.Docs do
  @moduledoc false

  def generate(spec) do
    {docs, sections, _level} = build_docs(spec[:keys], {[], [], 0})

    doc = if spec[:doc], do: "#{spec[:doc]}\n\n", else: ""
    to_string(["## Options\n\n#{doc}", Enum.reverse(docs), Enum.reverse(sections)])
  end

  defp build_docs(nil, acc) do
    acc
  end

  defp build_docs(keys, {docs, sections, level} = acc) do
    cond do
      keys[:*] ->
        build_docs(keys[:*][:keys], acc)

      keys ->
        Enum.reduce(keys, {docs, sections, level + 1}, &option_doc/2)

      true ->
        acc
    end
  end

  defp option_doc({key, {fun, spec}}, acc) when is_function(fun) do
    option_doc({key, spec}, acc)
  end

  defp option_doc({key, spec}, {docs, sections, level}) do
    doc_parts =
      (spec[:doc] || "")
      |> String.trim()
      |> String.split("\n\n", parts: 2, trim: true)

    doc_summary = Enum.at(doc_parts, 0)
    doc_body = Enum.at(doc_parts, 1)
    item_doc_str = doc_summary && String.trim_trailing(doc_summary, ".") <> "."

    description =
      [get_required_str(spec), item_doc_str, get_default_str(spec), get_options_str(spec)]
      |> Enum.reject(&is_nil/1)
      |> case do
        [] -> ""
        parts -> " - " <> Enum.join(parts, " ")
      end

    indent = String.duplicate("  ", level)
    doc = "#{indent}* `#{inspect(key)}`#{description}\n\n"

    if spec[:subsection] do
      build_docs_with_subsection(spec, doc, doc_body, {docs, sections, level})
    else
      build_docs(spec[:keys], {[doc | docs], sections, level})
    end
  end

  defp build_docs_with_subsection(spec, doc, doc_body, {docs, sections, level}) do
    {item_docs, sections, _level} = build_docs(spec[:keys], {[], sections, 0})
    section_title = "### #{spec[:subsection]}\n\n"

    doc_body =
      if doc_body do
        String.trim_trailing(doc_body, "\n") <> "\n\n"
      else
        ""
      end

    item_section = [section_title, doc_body | Enum.reverse(item_docs)]
    {[doc | docs], [item_section | sections], level}
  end

  defp get_required_str(spec) do
    spec[:required] && "Required."
  end

  defp get_default_str(spec) do
    if Keyword.has_key?(spec, :default) do
      "The default value is `#{inspect(spec[:default])}`."
    end
  end

  defp get_options_str(spec) do
    case {spec[:keys], spec[:subsection]} do
      {nil, nil} ->
        nil

      {_, nil} ->
        "Supported options:"

      {_, subsection} ->
        "See \"#{subsection}\" section below."
    end
  end
end
