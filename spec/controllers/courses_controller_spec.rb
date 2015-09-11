require 'rails_helper'

describe CoursesController do

  describe '#index' do
    context 'signed in user' do
      let!(:course) { create(:course, listed: true, submitted: true, start: 2.months.ago, end: 2.months.from_now) }
      let!(:user) { create(:admin) }
      let!(:signed_in) { true }
      let!(:permissions) { 1 }
      let!(:cohort) { create(:cohort) }
      before do
        allow(controller).to receive(:current_user).and_return(user)
        allow(controller).to receive(:user_signed_in?).and_return(signed_in)
        allow(user).to receive(:permissions) { permissions }
      end

      context 'admin' do
        let!(:courses_user) { create(:courses_user, course_id: course.id, user_id: user.id) }
        it 'sets admin courses  and user courses if user is an admin' do
          get :index, cohort: cohort.slug
          expect(assigns(:admin_courses)).to eq(Course.submitted_listed)
        end
      end

      context 'student' do
        let!(:user) { create(:test_user) }
        before { allow(controller).to receive(:current_user).and_return(user) }
        let!(:courses_user) { create(:courses_user, course_id: course.id, user_id: user.id) }
        it 'sets users courses' do
          get :index, cohort: cohort.slug
          expect(assigns(:user_courses)).to include(course)
        end
      end
    end

    context 'params has key of cohort' do
      let!(:user) { create(:admin) }
      let(:signed_in) { false }
      before do
        allow(controller).to receive(:current_user).and_return(user)
        allow(controller).to receive(:user_signed_in?).and_return(signed_in)
      end
      context 'cohort none in params' do
        let!(:course) { create(:course, id: 100000, listed: true, submitted: false) }
        it 'sets the courses to unsubmitted' do
          get :index, cohort: 'none'
          expect(assigns(:cohort)).to be_an_instance_of(OpenStruct)
          expect(assigns(:courses)).to eq(Course.unsubmitted_listed)
          expect(assigns(:trained)).to be_nil
        end
      end

      context 'default cohort in env' do
        let!(:cohort) { create(:cohort) }
        before do
          allow(Figaro).to receive_message_chain(:env, :default_cohort).and_return('spring_2015')
          allow(Figaro).to receive_message_chain(:env, :update_length).and_return(7)
        end
        it 'gets the slug' do
          get :index
          expect(assigns(:cohort)).to eq(cohort)
        end
      end

      describe 'cohort not in params; no default' do
        before(:example) { ENV['default_cohort'] = nil }
        after(:example)  { ENV['default_cohort'] = 'spring_2015' }
        it 'raises' do
          expect{get :index}.to raise_error(ActionController::RoutingError)
        end
      end
    end
  end

  describe '#destroy' do
    let!(:course)           { create(:course) }
    let!(:user)             { create(:test_user) }
    let!(:courses_users)    { create(:courses_user, course_id: course.id, user_id: user.id) }
    let!(:article)          { create(:article) }
    let!(:articles_courses) { create(:articles_course, course_id: course.id, article_id: article.id) }
    let!(:assignment)       { create(:assignment, course_id: course.id) }
    let!(:cohorts_courses)  { create(:cohorts_course, course_id: course.id) }
    let!(:week)             { create(:week, course_id: course.id) }
    let!(:gradeable)        { create(:gradeable, gradeable_item_type: 'Course', gradeable_item_id: course.id) }
    let!(:admin)            { create(:admin, id: 2) }

    before do
      allow(controller).to receive(:current_user).and_return(admin)
      controller.instance_variable_set(:@course, course)
    end

    it 'calls update methods on WikiEdits' do
      expect(WikiEdits).to receive(:update_assignments)
      expect(WikiEdits).to receive(:update_course)
      delete :destroy, id: "#{course.slug}.json", format: :json
    end

    context 'destroy callbacks' do
      before do
        allow(WikiEdits).to receive(:update_assignments)
        allow(WikiEdits).to receive(:update_course)
      end

      it 'destroys associated models' do
        delete :destroy, id: "#{course.slug}.json", format: :json

        %w(CoursesUsers ArticlesCourses CohortsCourses).each do |model|
          expect {
            # metaprogramming for: CoursesUser.find(courses_user.id)
            Object.const_get(model).send(:find, send(model.underscore).id)
          }.to raise_error(ActiveRecord::RecordNotFound), "#{model} did not raise"
        end

        %i(assignment week gradeable).each do |model|
          expect{
            # metaprogramming for: Assigment.find(assignment.id)
            model.to_s.classify.constantize.send(:find, send(model).id)
          }.to raise_error(ActiveRecord::RecordNotFound), "#{model} did not raise"
        end
      end

      it 'returns success' do
        delete :destroy, id: "#{course.slug}.json", format: :json
        expect(response).to be_success
      end

      it 'deletes the course' do
        delete :destroy, id: "#{course.slug}.json", format: :json
        expect(Course.find_by_slug(course.slug)).to be_nil
      end
    end
  end

  describe '#update' do
    let(:submitted_1) { false }
    let(:submitted_2) { false }
    let!(:course) { create(:course, submitted: submitted_1) }
    let(:user)    { create(:admin) }
    let(:course_params) {{
      title: 'New title',
      description: 'New description',
      # Don't use 2.months.ago; it'll return a datetime, not a date
      start: Date.today - 2.months,
      end: Date.today + 2.months,
      term: 'pizza',
      slug: 'food',
      subject: 'cooking',
      expected_students: 1,
      submitted: submitted_2,
      listed: false,
      day_exceptions: '',
      weekdays: '0001000',
      no_day_exceptions: true
    }}
    before do
      allow(controller).to receive(:current_user).and_return(user)
      allow(controller).to receive(:user_signed_in?).and_return(true)
      allow(WikiEdits).to receive(:update_course)
    end
    it 'updates all values' do
      put :update, id: course.slug, course: course_params, format: :json
      course_params.each do |key, value|
        expect(course.reload.send(key)).to eq(value)
      end
    end

    it 'sets timeline start/end to course start/end if not in params' do
      put :update, id: course.slug, course: course_params, format: :json
      expect(course.reload.timeline_start).to eq(course_params[:start])
      expect(course.reload.timeline_end).to eq(course_params[:end])
    end

    context 'setting passcode' do
      let(:course) { create(:course) }
      before { course.update_attribute(:passcode, nil) }
      it 'sets if it is nil and not in params' do
        put :update, id: course.slug, course: { title: 'foo' }, format: :json
        expect(course.reload.passcode).to match(/[a-z]{8}/)
      end
    end

    context 'setting instructor info' do
      let(:course_params) {{
        instructor_name: 'pizza',
        instructor_email: 'pizza@tacos.com'
      }}
      before do
        user.update_attributes(real_name: 'fakename', email: 'fake@example.com')
      end
      it 'sets the instructor name and email if they are in the params' do
        put :update, id: course.slug, course: course_params, format: :json
        expect(user.reload.real_name).to eq(course_params[:instructor_name])
        expect(user.reload.email).to eq(course_params[:instructor_email])
      end
    end

    it 'raises if course is not found' do
      expect { put :update, id: 'peanut-butter', course: course_params, format: :json }.to raise_error
    end

    it 'returns the new course as json' do
      put :update, id: course.slug, course: course_params, format: :json
      # created ats differ by milliseconds, so check relevant attrs
      expect(response.body['title']).to eq(course.reload.to_json['title'])
      expect(response.body['term']).to eq(course.reload.to_json['term'])
      expect(response.body['subject']).to eq(course.reload.to_json['subject'])
    end

    context 'course is not new' do
      let(:submitted_1) { true }
      let(:submitted_2) { true }
      it 'does not announce course' do
        expect(WikiEdits).not_to receive(:announce_course)
        put :update, id: course.slug, course: course_params, format: :json
      end
    end

    context 'course is new' do
      let(:submitted_2) { true }
      it 'announces course' do
        expect(WikiEdits).to receive(:announce_course)
        put :update, id: course.slug, course: course_params, format: :json
      end
    end
  end

  describe '#create' do
    describe 'setting slug from school/title/term' do
      let!(:user) { create(:admin) }
      let(:expected_slug) { 'Wiki_University/How_to_Wiki_(Fall_2015)' }

      before do
        allow(controller).to receive(:current_user).and_return(user)
        allow(controller).to receive(:user_signed_in?).and_return(true)
      end

      context 'all slug params present' do
        let(:course_params) {{
          school: 'Wiki University',
          title: 'How to Wiki',
          term: 'Fall 2015'
        }}
        it 'sets slug correctly' do
          post :create, course: course_params, format: :json
          expect(Course.last.slug).to eq(expected_slug)
        end
      end

      context 'not all slug params present' do
        let(:course_params) {{
          school: 'Wiki University',
          title: 'How to Wiki',
        }}
        it 'does not set slug' do
          post :create, course: course_params, format: :json
          expect(Course.last.slug).to be_nil
        end
      end
    end
  end

  describe '#list' do
    let(:course) { create(:course) }
    let(:cohort) { create(:cohort) }
    let(:user)   { create(:admin) }

    before do
      allow(controller).to receive(:current_user).and_return(user)
      allow(controller).to receive(:user_signed_in?).and_return(true)
    end

    context 'cohort is not found' do
      it 'gives a failure message' do
        post :list, id: course.slug, cohort: { title: 'non-existent-cohort' }
        expect(response.status).to eq(404)
        expect(response.body).to match(/Sorry/)
      end
    end

    context 'cohort is found' do
      context 'post request' do
        it 'creates a CohortsCourse' do
          post :list, id: course.slug, cohort: { title: cohort.title }, format: :json
          last_cohort = CohortsCourses.last
          expect(last_cohort.course_id).to eq(course.id)
          expect(last_cohort.cohort_id).to eq(cohort.id)
        end
      end

      context 'delete request' do
        let!(:cohorts_course) { create(:cohorts_course, cohort_id: cohort.id, course_id: course.id) }
        it 'deletes CohortsCourse' do
          delete :list, id: course.slug, cohort: { title: cohort.title }, format: :json
          expect(CohortsCourses.find_by(course_id: course.id, cohort_id: cohort.id)).to be_nil
        end
      end
    end
  end

  describe '#tag' do
    let(:course) { create(:course) }
    let(:user)   { create(:admin) }

    before do
      allow(controller).to receive(:current_user).and_return(user)
      allow(controller).to receive(:user_signed_in?).and_return(true)
    end

    context 'post request' do
      let(:tag) { 'pizza' }
      it 'creates a tag' do
        post :tag, id: course.slug, tag: { tag: tag }, format: :json
        expect(Tag.last.tag).to eq(tag)
        expect(Tag.last.course_id).to eq(course.id)
      end
    end

    context 'delete request' do
      let(:tag) { Tag.create(tag: 'pizza', course_id: course.id) }
      it 'deletes the tag' do
        delete :tag, id: course.slug, tag: { tag: tag.tag }, format: :json
        expect{ Tag.find(tag.id) }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
