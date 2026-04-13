#!/usr/bin/env bash

# for mode in no-rooted; do
#   bundle exec scripts/image2glam.rb --collid clark1ic --m_id 000080674 --$mode
#   bundle exec scripts/image2glam.rb --collid sclib --m_id 9015078576785 --$mode
#   bundle exec scripts/image2glam.rb --collid tinder --m_id 28855 --$mode
#   bundle exec scripts/image2glam.rb --collid tinder --m_id 3 --$mode
#   bundle exec scripts/image2glam.rb --collid yhsic1 --m_id 01027 --$mode
# done

bundle exec ./scripts/image2glam.rb --system_identifiers --output_path ../dor-sample-glams/inbox --stakeholder clements --collid tinder --m_id 3
bundle exec ./scripts/image2glam.rb --system_identifiers --output_path ../dor-sample-glams/inbox --collid yhsic1 --m_id 01027
bundle exec ./scripts/image2glam.rb --system_identifiers --output_path ../dor-sample-glams/inbox --stakeholder scrc --collid sclib --m_id 9015078576785
bundle exec ./scripts/image2glam.rb --system_identifiers --output_path ../dor-sample-glams/inbox --collid clark1ic --m_id 000080674
bundle exec ./scripts/image2glam.rb --system_identifiers --output_path ../dor-sample-glams/inbox --collid clark1ic --m_id 000081883
bundle exec ./scripts/image2glam.rb --system_identifiers --output_path ../dor-sample-glams/inbox --stakeholder bentley --collid bhl --m_id bl009764
bundle exec ./scripts/image2glam.rb --system_identifiers --output_path ../dor-sample-glams/inbox --stakeholder scrc --collid apis --m_id 18166