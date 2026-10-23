//! Carry each actual guest title's bounded metadata across fresh VM calls.
use super::*;
use dexvm::vm::object::Native;

fn continuation(ext: &mut Keiyoushi) -> Result<JValue, String> {
    let vm = ext.ctx().vm();
    let class = vm
        .ensure_class_by_desc("Lkotlin/coroutines/jvm/internal/ContinuationImpl;")
        .map_err(|e| e.to_string())?;
    vm.alloc_instance(class)
        .map(JValue::Obj)
        .map_err(|e| e.to_string())
}
pub(super) fn title(ext: &mut Keiyoushi, value: JValue) -> Result<Value, String> {
    let Some(Native::SManga {
        url,
        title,
        author,
        artist,
        description,
        genre,
        status,
        thumbnail_url,
        memo,
        ..
    }) = ext.ctx().vm().payload_of(value)
    else {
        return Err("The source returned invalid title details.".into());
    };
    Ok(
        json!({"url":url,"title":title,"author":author.unwrap_or_default(),
        "artist":artist.unwrap_or_default(),"description":description.unwrap_or_default(),
        "genre":genre.unwrap_or_default(),"status":status,"thumbnailURL":thumbnail_url,
        "memo":chapter_wire::memo(ext.ctx().vm(),memo)?}),
    )
}
pub(super) fn browse(
    ext: &mut Keiyoushi,
    src: &Source,
    command: &Command,
) -> Result<Value, String> {
    let cont = continuation(ext)?;
    let (name, sig, args) = match command.op.as_str() {
        "popular" => (
            "getPopularManga",
            "(ILkotlin/coroutines/Continuation;)Ljava/lang/Object;",
            vec![JValue::Int(command.page), cont],
        ),
        "latest" => (
            "getLatestUpdates",
            "(ILkotlin/coroutines/Continuation;)Ljava/lang/Object;",
            vec![JValue::Int(command.page), cont],
        ),
        _ => {
            let vm = ext.ctx().vm();
            let query = vm.alloc_string(&command.query);
            let filters = vm
                .alloc_native(
                    "Leu/kanade/tachiyomi/source/model/FilterList;",
                    Native::SFilterList(vec![]),
                )
                .map_err(|e| e.to_string())?;
            ("getSearchManga", "(ILjava/lang/String;Leu/kanade/tachiyomi/source/model/FilterList;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;", vec![JValue::Int(command.page),query,filters,cont])
        }
    };
    let out = ext
        .ctx()
        .invoke_on(src.inst(), name, sig, &args)
        .map_err(|e| ext.describe_error(&e))?;
    let Some(Native::SMangasPage { mangas, has_next }) = ext.ctx().vm().payload_of(out) else {
        return Err("The source returned an invalid title list.".into());
    };
    if mangas.len() > 10000 {
        return Err("The source returned too many titles.".into());
    }
    let mangas = mangas
        .into_iter()
        .map(|m| title(ext, m))
        .collect::<Result<Vec<_>, _>>()?;
    Ok(json!({"mangas":mangas,"hasNext":has_next}))
}
pub(super) fn update(
    ext: &mut Keiyoushi,
    src: &Source,
    input: &MangaInput,
    details: bool,
    chapters: bool,
) -> Result<JValue, String> {
    let vm = ext.ctx().vm();
    let memo = chapter_wire::decode_memo(vm, input.memo.as_deref())?;
    let optional = |s: &String| if s.is_empty() { None } else { Some(s.clone()) };
    let manga = vm
        .alloc_native(
            "Leu/kanade/tachiyomi/source/model/SManga;",
            Native::SManga {
                url: input.url.clone(),
                title: input.title.clone(),
                author: optional(&input.author),
                artist: optional(&input.artist),
                description: optional(&input.description),
                genre: optional(&input.genre),
                status: input.status,
                thumbnail_url: input.thumbnail_url.clone(),
                update_strategy: JValue::Null,
                memo,
            },
        )
        .map_err(|e| e.to_string())?;
    let list = vm
        .alloc_native("Ljava/util/ArrayList;", Native::List(vec![]))
        .map_err(|e| e.to_string())?;
    let cont = continuation(ext)?;
    ext.ctx().invoke_on(src.inst(),"getMangaUpdate",
        "(Leu/kanade/tachiyomi/source/model/SManga;Ljava/util/List;ZZLkotlin/coroutines/Continuation;)Ljava/lang/Object;",
        &[manga,list,JValue::Int(i32::from(details)),JValue::Int(i32::from(chapters)),cont])
        .map_err(|e|ext.describe_error(&e))
}
