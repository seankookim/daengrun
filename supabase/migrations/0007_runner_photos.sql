-- 0007: 러너 프로필 갤러리 — 스토어프런트 사진 (avatars 버킷 {uid}/gallery/* 재사용)
alter table runners add column if not exists photos text[] not null default '{}';
