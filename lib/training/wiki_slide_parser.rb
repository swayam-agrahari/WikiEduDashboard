# frozen_string_literal: true

require_dependency "#{Rails.root}/lib/wikitext"

#= Takes wikitext for an on-wiki slide and extracts title and content
class WikiSlideParser
  def initialize(wikitext)
    @wikitext = wikitext&.dup || +''
    set_utf8_encoding
    remove_noinclude
    remove_translation_markers
    remove_translate_tags
    remove_span_tags
    extract_quiz_template
    extract_category_templates # only relevant for TrainingLibrary
    convert_image_templates
    convert_video_templates
    convert_button_templates
  end

  # The first translated line is the slide title
  def title
    return '' if @wikitext.blank?
    # get the first non-blank line
    title = @wikitext.strip.lines.first.chomp
    # remove header markup for level 2 or lower
    title.gsub(/==+/, '').strip
  end

  # Everything after the first translated line is the slide content
  def content
    return '' if @wikitext.blank?
    wikitext = @wikitext.lines.drop(1).join # First line is the title
    wikitext[0] = '' while wikitext[0] == "\n" # Remove leading newlines
    markdown = Wikitext.mediawiki_to_markdown(wikitext)
    # Make sure first line after a figure gets parsed as a new paragraph
    markdown.gsub("figure>\n", "figure>\n\n")
  end

  def quiz
    return unless @quiz_template
    { correct_answer_id: quiz_correct_answer,
      question: quiz_question,
      answers: quiz_answers }
  end

  # Only applies to TrainingLibrary
  def categories
    @category_templates.map do |template|
      category_hash_from_template(template[0])
    end
  end

  private

  def set_utf8_encoding
    @wikitext = @wikitext.force_encoding('UTF-8')
  end

  def remove_noinclude
    @wikitext.gsub!(%r{<noinclude>.*?</noinclude>\n*}m, '')
  end

  def remove_translation_markers
    # Remove both marker and any trailing whitespace after it,
    # which may interfere with correct markdown conversion.
    # Matches any amount of horizontal whitespace (\h) but at most
    # one newline, to prevent concatenating the title with the contents.
    @wikitext.gsub!(/<!--.+?-->\h*\n??/, '')
  end

  def remove_translate_tags
    # Remove both the tags and any excess whitespace within them,
    # which may interfere with correct markdown conversion.
    @wikitext.gsub!(/<translate>\s*/, '')
    @wikitext.gsub!(%r{\s*</translate>}, '')
    @wikitext.gsub!(/<tvar.*?>/, '')
    @wikitext.gsub!(%r{</>}, '')
  end

  def remove_span_tags
    # Remove both the tags and any excess whitespace within them,
    # Aim is to get rid of <span lang="en" dir="ltr" class="mw-content-ltr">
    # that may appear in cas of incomplete translations.
    @wikitext.gsub!(/<span .*?>\s*/, '')
    @wikitext.gsub!(%r{\s*</span>}, '')
  end

  def extract_quiz_template
    @wikitext.gsub!(/(?<template>{{Training module quiz.*?\n}})/m, '')
    @quiz_template = Regexp.last_match && Regexp.last_match['template']
  end

  def quiz_correct_answer
    # Looks like:
    # | correct_answer_id = 3
    Integer(template_parameter_value(@quiz_template, 'correct_answer_id'))
  end

  def quiz_question
    # Looks like:
    # | question = What... is your favorite colour?
    template_parameter_value(@quiz_template, 'question')
  end

  def quiz_answers
    answers = (1..9).map do |answer_number|
      answer_hash(answer_number)
    end
    answers.compact
  end

  def answer_hash(number)
    text = template_parameter_value(@quiz_template, "answer_#{number}")
    return unless text
    explanation = template_parameter_value(@quiz_template, "explanation_#{number}")
    { id: number,
      text:,
      explanation: }
  end

  def convert_image_templates
    # Get all the image templates on the page to allow for multiple images in the same slide
    image_templates = @wikitext.scan(/(?<image>{{Training module image.*?\n}})/im)
    return unless image_templates
    # Replace each one with the correct figure markup
    image_templates.each do |template|
      @wikitext.sub! template[0], figure_markup_from_template(template[0])
    end
  end

  def convert_video_templates
    # Get all the video templates on the page to allow for multiple videos in the same slide
    video_templates = @wikitext.scan(/(?<video>{{Training module video.*?\n}})/im)
    return unless video_templates
    # Replace each one with the correct video markup
    video_templates.each do |template|
      @wikitext.sub! template[0], video_markup_from_template(template[0])
    end
  end

  def convert_button_templates
    # Get all the button templates on the page to allow for multiple buttons in the same slide
    button_templates = @wikitext.scan(/(?<button>{{Training module button.*?\n}})/im)
    return unless button_templates
    # Replace each one with the correct button markup
    button_templates.each do |template|
      @wikitext.sub! template[0], button_markup_from_template(template[0])
    end
  end

  def figure_markup_from_template(template)
    image_layout = template_parameter_value(template, 'layout')
    image_source = template_parameter_value(template, 'source')
    image_filename = template_parameter_value(template, 'image')
    image_caption = template_parameter_value(template, 'caption')
    image_credit = template_parameter_value(template, 'credit')
    <<~FIGURE
      <figure class="#{image_layout}"><img src="#{image_source}" />
      <figcaption class="#{'image-credit' if image_credit}">#{image_caption}
      <a href="https://commons.wikimedia.org/wiki/#{image_filename}">#{image_credit}</a>
      </figcaption>
      </figure>
    FIGURE
  end

  def video_markup_from_template(template)
    video_source = template_parameter_value(template, 'source')
    <<~VIDEO
      <iframe width="420" height="315" src="#{video_source}" frameborder="0" allowfullscreen></iframe>
    VIDEO
  end

  def button_markup_from_template(template)
    button_text = template_parameter_value(template, 'text')
    button_link = template_parameter_value(template, 'link')
    <<~BUTTON
      <div class="training__button-container"><a target="_blank" class="btn btn-primary" href="#{button_link}">
      #{button_text}
      </a></div>
    BUTTON
  end

  # Template for a category of modules, in a TrainingLibrary
  # See for example https://meta.wikimedia.org/wiki/Training_modules/editathons/library
  def extract_category_templates
    # First get the wikitext for each instance of the template
    @category_templates = @wikitext.scan(/(?<template>{{Training module category.*?\n}})/im)
    # Then remove the templates from the wikitext, so they don't get included in the description
    @wikitext.gsub!(/(?<template>{{Training module category.*?\n}})/m, '')
  end

  def category_hash_from_template(template)
    {
      'title' => template_parameter_value(template, 'title'),
      'description' => template_parameter_value(template, 'description'),
      'modules' => module_hashes_from_template(template)
    }
  end

  def module_hashes_from_template(template)
    modules = (1..9).map do |module_number|
      module_hash(template, module_number)
    end
    modules.compact
  end

  def module_hash(template, module_number)
    module_name = template_parameter_value(template, "module_name_#{module_number}")
    return nil unless module_name
    {
      'slug' => template_parameter_value(template, "module_slug_#{module_number}"),
      'name' => module_name,
      'description' => template_parameter_value(template, "module_description_#{module_number}")
    }
  end

  def template_parameter_value(template, parameter)
    # Extract value from the template
    # The expected format is: | parameter_name = value
    # The regex breakdown:
    # - \|:            Matches the pipe character at the start of the parameter line.
    # - \s*:           Matches any whitespace characters (spaces or tabs) after the pipe.
    # - #{parameter}:  Inserts the parameter name to match.
    # - \s*=\s*:       Matches the equals sign with optional whitespace around it.
    # - (?<value>.*?): Captures the value after the equals sign into a named group 'value'.
    # - (?=\||\Z):     Positive lookahead to ensure the match ends at the next pipe
    #                   or the end of the string.
    match = template.match(/\|\s*#{parameter}\s*=\s*(?<value>.*?)(?=\||\Z)/m)

    # Check if match is present and value is not nil
    value = match && match['value']

    # Remove undesired formatting and whitespace, only if value is not nil
    # The gsub removes leading colons and triple quotes, and strip removes surrounding whitespace.
    value ? value.gsub(/(^:|''')/, '').strip : nil
  end
end
