#!/usr/bin/env bash

for mode in no-rooted; do
  bundle exec scripts/image2glam.rb --collid clark1ic --m_id 000080674 --$mode
  bundle exec scripts/image2glam.rb --collid sclib --m_id 9015078576785 --$mode
  bundle exec scripts/image2glam.rb --collid tinder --m_id 28855 --$mode
  bundle exec scripts/image2glam.rb --collid tinder --m_id 3 --$mode
  bundle exec scripts/image2glam.rb --collid yhsic1 --m_id 01027 --$mode
done