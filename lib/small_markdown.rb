# encoding: UTF-8

# SmallMarkdown version 1.0.0
#
# Transforme du Markdown spécifique aux notes en HTML
#

require "cgi"

class SmallMarkdown

  def initialize content
    @buffer = ""
    @only_li = true
    @ul_count = 0
    @inside_code = false
    @inside_p = false
    @inside_ul = false
    @inside_li = false
    lines = content.split("\n")
    lines.each_index do |i|
      line = lines[i]
      next_line = lines[i + 1] || ""
      line = append_code(line)
      line = append_level1(line)
      line = append_level2(line)
      line = append_li(line, next_line)
      line = append_text(line, next_line)
    end
  end

  def to_html
    end_p
    end_li
    end_ul

    if (@only_li) && (@ul_count > 1)
      @buffer = @buffer.gsub("<li>", "  <p>")
      @buffer = @buffer.gsub("</li>", "</p>")
      @buffer = @buffer.gsub("<ul>", "  <li>")
      @buffer = @buffer.gsub("</ul>", "  </li>")
      @buffer = "<ol>\n#{@buffer}\n</ol>"
    end

    @buffer
  end

  private

  def start_code
    @only_li = false
    end_p
    end_ul
    @buffer << "<pre>"
    @inside_code = true
  end

  def end_code
    @buffer << "</pre>\n"
    @inside_code = false
  end

  def start_p
    return if @inside_p
    @only_li = false
    end_ul
    @buffer << "<p>\n"
    @inside_p = true
  end

  def end_p
    return unless @inside_p
    @buffer << "</p>\n"
    @inside_p = false
  end

  def start_ul
    return if @inside_ul
    @ul_count += 1
    end_p
    @buffer << "<ul>\n"
    @inside_ul = true
  end

  def end_li
    return unless @inside_li
    @buffer << "</li>\n"
    @inside_li = false
  end

  def end_ul
    return unless @inside_ul
    return if @inside_li
    @buffer << "</ul>\n"
    @inside_ul = false
  end

  def append_code line
    return nil if line.nil?
    if line.start_with?("```")
      if @inside_code
        end_code
      else
        start_code
      end
      line = nil
    elsif @inside_code
      @buffer << CGI::escape_html(line)
      line = nil
    end
    line
  end

  def append_level1 line
    return nil if line.nil?
    if line.start_with?("# ")
      @only_li = false
      end_p
      end_li
      end_ul
      @buffer << "\n<h3>#{line.chomp.slice(2..-1)}</h3>\n"
      line = nil
    end
    line
  end

  def append_level2 line
    return nil if line.nil?
    if line.start_with?("##")
      @only_li = false
      end_p
      end_li
      end_ul
      @buffer << "\n<h4>#{line.chomp.slice(3..-1)}</h4>\n"
      line = nil
    end
    line
  end

  def append_li line, next_line
    return nil if line.nil?
    if line.start_with?("* ")
      end_p
      start_ul
      @buffer << "</li>\n" if @inside_li
      @inside_li = false
      @buffer << "  <li>#{md_text(line.chomp.slice(2..-1))}"
      if next_line.start_with?("* ")
        @buffer << "</li>\n"
      elsif next_line.strip.empty?
        @buffer << "</li>\n"
      else
        @buffer << "\n"
        @inside_li = true
      end
      line = nil
    end
    line
  end

  def append_text line, next_line
    return nil if line.nil?
    if line.strip.empty?
      end_p
      end_li
      end_ul
    else
      unless @inside_p
        end_ul
        start_p
      end
      @buffer << "  " + md_text(line)
      @buffer << "<br>" if line.strip.start_with?("- ") && next_line.strip.start_with?("- ")
      line = nil
    end
    line
  end

  def md_text(text)
    text = text.gsub(/(https?:\/\/[^ ]+)/, '<a href="\1">\1</a>')
    text = text.sub(/`/, '<kbd>')
    text = text.sub(/`/, '</kbd>')
    text = text.gsub(/=>/, "<strong>⇒</strong>") #"
    text
  end

end
