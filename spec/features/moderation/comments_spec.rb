require 'rails_helper'

feature 'Moderate Comments' do

  feature 'Hiding Comments' do

    scenario 'Hide', :js do
      citizen = create(:user)
      moderator = create(:moderator)

      debate = create(:debate)
      comment = create(:comment, commentable: debate, body: 'SPAM')

      login_as(moderator.user)
      visit debate_path(debate)

      within("#comment_#{comment.id}") do
        click_link 'Hide'
        expect(page).to have_css('.comment .faded')
      end

      login_as(citizen)
      visit debate_path(debate)

      expect(page).to have_css('.comment', count: 1)
      expect(page).to have_content('This comment has been deleted')
      expect(page).to_not have_content('SPAM')
    end

    scenario 'Children visible', :js do
      citizen = create(:user)
      moderator = create(:moderator)

      debate = create(:debate)
      comment = create(:comment, commentable: debate, body: 'SPAM')
      create(:comment, commentable: debate, body: 'Acceptable reply', parent_id: comment.id)

      login_as(moderator.user)
      visit debate_path(debate)

      within("#comment_#{comment.id}") do
        first(:link, "Hide").click
        expect(page).to have_css('.comment .faded')
      end

      login_as(citizen)
      visit debate_path(debate)

      expect(page).to have_css('.comment', count: 2)
      expect(page).to have_content('This comment has been deleted')
      expect(page).to_not have_content('SPAM')

      expect(page).to have_content('Acceptable reply')
    end
  end

  scenario 'Moderator actions in the comment' do
    citizen = create(:user)
    moderator = create(:moderator)

    debate = create(:debate)
    comment = create(:comment, commentable: debate)

    login_as(moderator.user)
    visit debate_path(debate)

    within "#comment_#{comment.id}" do
      expect(page).to have_link("Hide")
      expect(page).to have_link("Ban author")
    end

    login_as(citizen)
    visit debate_path(debate)

    within "#comment_#{comment.id}" do
      expect(page).to_not have_link("Hide")
      expect(page).to_not have_link("Ban author")
    end
  end

  scenario 'Moderator actions do not appear in own comments' do
    moderator = create(:moderator)

    debate = create(:debate)
    comment = create(:comment, commentable: debate, user: moderator.user)

    login_as(moderator.user)
    visit debate_path(debate)

    within "#comment_#{comment.id}" do
      expect(page).to_not have_link("Hide")
      expect(page).to_not have_link("Ban author")
    end
  end

  feature '/moderation/ menu' do

    background do
      moderator = create(:moderator)
      login_as(moderator.user)
    end

    scenario "Current filter is properly highlighted" do
      visit moderation_comments_path
      expect(page).to_not have_link('All')
      expect(page).to have_link('Pending')
      expect(page).to have_link('Reviewed')

      visit moderation_comments_path(filter: 'all')
      expect(page).to_not have_link('All')
      expect(page).to have_link('Pending')
      expect(page).to have_link('Reviewed')

      visit moderation_comments_path(filter: 'pending_review')
      expect(page).to have_link('All')
      expect(page).to_not have_link('Pending')
      expect(page).to have_link('Reviewed')

      visit moderation_comments_path(filter: 'reviewed')
      expect(page).to have_link('All')
      expect(page).to have_link('Pending')
      expect(page).to_not have_link('Reviewed')
    end

    scenario "Filtering comments" do
      create(:comment, :flagged_as_inappropiate, body: "Pending comment")
      create(:comment, :flagged_as_inappropiate, :hidden, body: "Hidden comment")
      create(:comment, :flagged_as_inappropiate, :reviewed, body: "Reviewed comment")

      visit moderation_comments_path(filter: 'all')
      expect(page).to have_content('Pending comment')
      expect(page).to_not have_content('Hidden comment')
      expect(page).to have_content('Reviewed comment')

      visit moderation_comments_path(filter: 'pending_review')
      expect(page).to have_content('Pending comment')
      expect(page).to_not have_content('Hidden comment')
      expect(page).to_not have_content('Reviewed comment')

      visit moderation_comments_path(filter: 'reviewed')
      expect(page).to_not have_content('Pending comment')
      expect(page).to_not have_content('Hidden comment')
      expect(page).to have_content('Reviewed comment')
    end

    scenario "Reviewing links remember the pagination setting and the filter" do
      per_page = Kaminari.config.default_per_page
      (per_page + 2).times { create(:comment, :flagged_as_inappropiate) }

      visit moderation_comments_path(filter: 'pending_review', page: 2)

      click_link('Mark as reviewed', match: :first)

      uri = URI.parse(current_url)
      query_params = Rack::Utils.parse_nested_query(uri.query).symbolize_keys

      expect(query_params[:filter]).to eq('pending_review')
      expect(query_params[:page]).to eq('2')
    end

    feature 'A flagged comment exists' do

      background do
        debate = create(:debate, title: 'Democracy')
        @comment = create(:comment, :flagged_as_inappropiate, commentable: debate, body: 'spammy spam')
        visit moderation_comments_path
      end

      scenario 'It is displayed with the correct attributes' do
        within("#comment_#{@comment.id}") do
          expect(page).to have_link('Democracy')
          expect(page).to have_content('spammy spam')
          expect(page).to have_content('1')
          expect(page).to have_link('Hide')
          expect(page).to have_link('Mark as reviewed')
        end
      end

      scenario 'Hiding the comment' do
        within("#comment_#{@comment.id}") do
          click_link('Hide')
        end

        expect(current_path).to eq(moderation_comments_path)
        expect(page).to_not have_selector("#comment_#{@comment.id}")

        expect(@comment.reload).to be_hidden
      end

      scenario 'Marking the comment as reviewed' do
        within("#comment_#{@comment.id}") do
          click_link('Mark as reviewed')
        end

        expect(current_path).to eq(moderation_comments_path)

        within("#comment_#{@comment.id}") do
          expect(page).to have_content('Reviewed')
        end

        expect(@comment.reload).to be_reviewed
      end
    end
  end
end
