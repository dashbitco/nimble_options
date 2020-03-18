defmodule NimbleOptions.Docs do
  @moduledoc false

  def generate(spec) do
    {docs, sections, _level} = build_docs(spec, {[], [], 0})

    doc = if spec[:doc], do: "#{spec[:doc]}\n\n", else: ""
    to_string(["## Options\n\n#{doc}", Enum.reverse(docs), Enum.reverse(sections)])
  end

  defp build_docs(spec, {docs, sections, level} = acc) do
    cond do
      spec[:keys][:*] ->
        build_docs(spec[:keys][:*], acc)

      spec[:keys] ->
        Enum.reduce(spec[:keys], {docs, sections, level + 1}, &option_doc/2)

      true ->
        acc
    end
  end

  defp build_docs_with_subsection(spec, {docs, sections, level}) do
    {section_title, section_body} = split_section(spec[:subsection])

    section_title = "### #{section_title}\n\n"

    section_body =
      case section_body do
        nil ->
          ""

        body ->
          String.trim_trailing(body, "\n") <> "\n\n"
      end

    {item_docs, sections, _level} = build_docs(spec, {[], sections, 0})
    item_section = [section_title, section_body | Enum.reverse(item_docs)]

    {docs, [item_section | sections], level}
  end

  defp option_doc({key, {fun, spec}}, acc) when is_function(fun) do
    option_doc({key, spec}, acc)
  end

  defp option_doc({key, spec}, {docs, sections, level}) do
    description =
      [get_required_str(spec), get_doc_str(spec), get_default_str(spec), get_options_str(spec)]
      |> Enum.reject(&is_nil/1)
      |> case do
        [] -> ""
        parts -> " - " <> Enum.join(parts, " ")
      end

    indent = String.duplicate("  ", level)
    doc = indent_doc("* `#{inspect(key)}`#{description}\n\n", indent)
    acc = {[doc | docs], sections, level}

    if spec[:subsection] do
      build_docs_with_subsection(spec, acc)
    else
      build_docs(spec, acc)
    end
  end

  defp get_doc_str(spec) do
    case String.trim(spec[:doc] || "") do
      "" ->
        nil

      doc ->
        String.trim_trailing(doc, ".") <> "."
    end
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
    {section_title, _} = split_section(spec[:subsection])

    case {spec[:keys], section_title} do
      {nil, nil} ->
        nil

      {_, nil} ->
        "Supported options:"

      {_, subsection} ->
        "See \"#{subsection}\" section below."
    end
  end

  defp split_section(text) do
    parts =
      (text || "")
      |> String.trim()
      |> String.split("\n\n", parts: 2, trim: true)

    {Enum.at(parts, 0), Enum.at(parts, 1)}
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
