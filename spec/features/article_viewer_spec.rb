# frozen_string_literal: true

require 'rails_helper'

describe 'Article Viewer', type: :feature, js: true do
  let(:course) { create(:course, start: '2017-01-01', end: '2020-01-01') }
  let(:user) { create(:user, username: 'Ragesoss') }
  let(:article) { create(:article, title: 'Nancy_Tuana') }
  let(:instructor) { create(:user, username: 'Instructor') }

  before do
    course.campaigns << Campaign.first
    create(:courses_user, course:, user:)
    create(:courses_user, course:, user: instructor,
                          role: CoursesUsers::Roles::INSTRUCTOR_ROLE)
    create(:articles_course, course:, article:, user_ids: [user.id])
  end

  it 'shows list of students who edited the article' do
    pending 'This fails on CI because of a CORS error, possible related to an outdated polyfill'

    visit "/courses/#{course.slug}/articles"
    find('button.icon-article-viewer').click
    expect(page).to have_content("Edits by: \nRagesoss", wait: 10)
    # once authorship date loads
    within(:css, '.article-viewer-legend.user-legend-name.user-highlight-1', wait: 20) do
      # click to scroll to next highlight
      find('img.user-legend-hover').click
    end

    pass_pending_spec
  end

  it 'lets an instructor report bad work' do
    pending 'This fails on CI because of a CORS error, possible related to an outdated polyfill'

    stub_token_request
    login_as(instructor)
    visit "/courses/#{course.slug}/articles"
    find('button.icon-article-viewer').click
    expect(page).to have_content("Edits by: \nRagesoss", wait: 10)
    find('a', text: 'Quality Problems?').click
    fill_in 'submit-bad-work-alert', with: 'Something has gone terribly wrong'
    click_button 'Notify Wiki Expert'
    expect(page).to have_content('Thank you! Contact your Wiki Expert')

    pass_pending_spec
  end
end
