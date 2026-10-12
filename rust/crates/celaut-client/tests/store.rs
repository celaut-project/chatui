//! The stores of last-seen advertisements.

use celaut_client::{FilePeerStore, MemoryPeerStore, PeerStore, Seen};

fn seen(ts: i64) -> Seen {
    Seen {
        ts,
        digest: format!("d{ts}"),
    }
}

fn exercise(store: &dyn PeerStore) {
    assert_eq!(store.get("a").unwrap(), None);
    store.put("a", seen(5)).unwrap();
    store.put("b", seen(7)).unwrap();
    assert_eq!(store.get("a").unwrap(), Some(seen(5)));
    store.put("a", seen(9)).unwrap();
    assert_eq!(store.get("a").unwrap(), Some(seen(9)));
    // An older value does not replace a newer one.
    store.put("a", seen(6)).unwrap();
    assert_eq!(store.get("a").unwrap(), Some(seen(9)));
    assert_eq!(store.get("b").unwrap(), Some(seen(7)));
}

#[test]
fn memory_store() {
    exercise(&MemoryPeerStore::new());
}

fn temp_path(name: &str) -> std::path::PathBuf {
    let dir =
        std::env::temp_dir().join(format!("celaut-client-test-{}-{name}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    dir.join("peers.json")
}

#[test]
fn file_store_keeps_values_between_instances() {
    let path = temp_path("file");
    let _ = std::fs::remove_file(&path);
    exercise(&FilePeerStore::new(&path));
    // A new instance reads the same file.
    let again = FilePeerStore::new(&path);
    assert_eq!(again.get("a").unwrap(), Some(seen(9)));
    std::fs::remove_dir_all(path.parent().unwrap()).unwrap();
}

#[test]
fn file_store_does_not_forget_on_a_bad_file() {
    let path = temp_path("bad");
    std::fs::write(&path, b"{not json").unwrap();
    let store = FilePeerStore::new(&path);
    assert!(store.get("a").is_err());
    assert!(store.put("a", seen(1)).is_err());
    // The bad file is still there.
    assert_eq!(std::fs::read(&path).unwrap(), b"{not json");
    std::fs::remove_dir_all(path.parent().unwrap()).unwrap();
}
