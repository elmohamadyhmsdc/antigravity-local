"""Small desktop view of illustrated character identities and their source media."""
import streamlit as st


def render_characters(ctx):
    db = ctx.db
    st.caption("Appearance groups use hair/head, clothing, visual details and body shape. "
               "Similar designs, outfit changes and occlusion can need correction.")
    by_identity = {}
    for sample in db.character_samples.values():
        by_identity.setdefault(sample['identity_id'], []).append(sample)
    if not by_identity:
        st.info("Enable Cartoon / anime sources in Gallery scan options, choose illustrated sources, then scan. "
                "Detection uses the installed HumanArt body model; human face detection is not required.")
        return
    for pid, samples in sorted(by_identity.items(), key=lambda item: (-len(item[1]), item[0])):
        identity = db.character_identities[pid]
        with st.expander(f"{identity.get('name') or f'Character {pid}'} · {len(samples)} appearances"):
            name = st.text_input("Character name", value=identity.get('name') or '', max_chars=80, key=f'char_name_{pid}')
            if st.button("Save name", key=f'char_save_{pid}'):
                identity['name'] = name.strip() or None
                db.save_db()
                ctx.after_change("Character renamed")
                st.rerun()
            # Bound work on large video libraries; the source opens in the existing inspector.
            pages = max(1, (len(samples) + 23) // 24)
            page = int(st.number_input("Page", 1, pages, 1, key=f'char_page_{pid}'))
            for sample in sorted(samples, key=lambda s: -s['score'])[(page-1)*24:page*24]:
                image, info = st.columns([1, 3])
                with image:
                    path = sample.get('crop_path')
                    if path:
                        from pathlib import Path
                        if Path(path).is_file():
                            st.image(path, width=140)
                with info:
                    media = db.get_media(sample['media_id']) or {}
                    st.write(media.get('name') or 'Source unavailable')
                    if sample.get('timestamp') is not None:
                        st.caption(f"At {sample['timestamp']:.2f} seconds")
                    if media and st.button("Open source", key=f"char_open_{sample['id']}"):
                        st.session_state['gal_inspect'] = media['path']
                        st.rerun()
                    if len(samples) > 1 and st.button("Separate this character", key=f"char_split_{sample['id']}"):
                        new_id = db.next_character_identity_id
                        db.next_character_identity_id += 1
                        db.character_identities[new_id] = dict(id=new_id, name=None, created_at=sample['created_at'])
                        sample['identity_id'] = new_id
                        db.save_db()
                        ctx.after_change("Character separated")
                        st.rerun()
