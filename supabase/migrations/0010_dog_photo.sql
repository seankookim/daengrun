-- 0010: 반려견 프로필 사진 (avatars 버킷 {uid}/dogs/* 재사용)
alter table dogs add column if not exists photo_url text;
