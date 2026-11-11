//! droiddock-engine: the adb engine behind the DroidDock Mac app.
//!
//! Each call is one command. The result is one JSON object on stdout:
//! success → the data (exit 0); failure → {"error": "..."} (exit 1).
//!
//!   version                         engine version
//!   devices                         phones adb knows, plus recent Wi-Fi addresses
//!   mdns                            phones that announce Wireless debugging on this network
//!   ls <serial> <path>              list a phone folder
//!   pull <serial> <mac_dir> <path>...   copy phone files/folders to the Mac
//!   push <serial> <phone_dir> <file>... copy Mac files/folders to the phone
//!   connect <addr> | pair <addr> <code> | disconnect <serial>
//!   usb-to-wifi <serial>            classic Wi-Fi adb on port 5555 (NOT encrypted)
//!   wifi-off <serial>               turn classic Wi-Fi adb off again
//!   forget <addr>
//!   head <serial> <path> <bytes> <out_file>   save the start of a phone file (0 = all)

use serde_json::{Value, json};
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

// ---------- helpers ----------

fn home() -> PathBuf {
    PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| "/tmp".into()))
}

fn state_dir() -> PathBuf {
    home().join("Library/Application Support/DroidDock")
}

fn adb() -> Result<PathBuf, String> {
    let mut candidates: Vec<PathBuf> = std::env::var("PATH")
        .unwrap_or_default()
        .split(':')
        .map(|d| Path::new(d).join("adb"))
        .collect();
    candidates.push("/opt/homebrew/bin/adb".into());
    candidates.push("/usr/local/bin/adb".into());
    candidates.push(home().join("Library/Android/sdk/platform-tools/adb"));
    candidates
        .into_iter()
        .find(|p| p.is_file())
        .ok_or_else(|| "adb is not installed. In Terminal, run: brew install android-platform-tools".into())
}

type Out = (bool, String, String);

/// Run adb and wait for it to finish.
fn run(args: &[&str]) -> Result<Out, String> {
    let out = Command::new(adb()?)
        .args(args)
        .stdin(Stdio::null())
        .output()
        .map_err(|e| format!("could not start adb: {e}"))?;
    Ok((
        out.status.success(),
        String::from_utf8_lossy(&out.stdout).into_owned(),
        String::from_utf8_lossy(&out.stderr).into_owned(),
    ))
}

/// Run adb, but stop it after `secs` seconds (for network calls that can hang).
fn run_timeout(args: &[&str], secs: u64) -> Result<Out, String> {
    let mut child = Command::new(adb()?)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("could not start adb: {e}"))?;
    let reader = |mut r: Box<dyn Read + Send>| {
        thread::spawn(move || {
            let mut s = String::new();
            let _ = r.read_to_string(&mut s);
            s
        })
    };
    let so = reader(Box::new(child.stdout.take().unwrap()));
    let se = reader(Box::new(child.stderr.take().unwrap()));
    let start = Instant::now();
    let status = loop {
        if let Some(st) = child.try_wait().map_err(|e| e.to_string())? {
            break st;
        }
        if start.elapsed() > Duration::from_secs(secs) {
            let _ = child.kill();
            let _ = child.wait();
            return Err("The phone did not answer in time. Check that it is on the same Wi-Fi.".into());
        }
        thread::sleep(Duration::from_millis(100));
    };
    Ok((status.success(), so.join().unwrap_or_default(), se.join().unwrap_or_default()))
}

fn tail(s: &str) -> String {
    let s = s.trim();
    let start = s.char_indices().rev().nth(299).map(|(i, _)| i).unwrap_or(0);
    s[start..].to_string()
}

/// Quote a string for the phone's sh.
fn shq(s: &str) -> String {
    format!("'{}'", s.replace('\'', r"'\''"))
}

// ---------- recent Wi-Fi addresses ----------

fn recent_path() -> PathBuf {
    state_dir().join("recent.txt")
}

fn recent() -> Vec<String> {
    fs::read_to_string(recent_path())
        .unwrap_or_default()
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .map(String::from)
        .collect()
}

fn remember(addr: &str) {
    let mut list: Vec<String> = recent().into_iter().filter(|a| a != addr).collect();
    list.insert(0, addr.to_string());
    list.truncate(8);
    let _ = fs::create_dir_all(state_dir());
    let _ = fs::write(recent_path(), list.join("\n"));
}

fn forget(addr: &str) -> Result<Value, String> {
    let list: Vec<String> = recent().into_iter().filter(|a| a != addr).collect();
    let _ = fs::write(recent_path(), list.join("\n"));
    Ok(json!({ "ok": true }))
}

// ---------- commands ----------

fn is_wifi(serial: &str) -> bool {
    serial.contains(':') || serial.contains("._adb-tls-connect")
}

/// Is this connection encrypted?
/// USB: yes (no network). Android "Wireless debugging" (paired, TLS): yes; it uses an
/// mDNS name or a random high port. Classic `adb tcpip` mode: NO; it uses port 5555.
/// adb does not report TLS directly, so port 5555 is the sign of the classic mode.
fn is_secure(serial: &str) -> bool {
    if serial.contains("._adb-tls-connect") || !serial.contains(':') {
        return true;
    }
    !serial.ends_with(":5555")
}

fn devices() -> Result<Value, String> {
    let (_, out, _) = run(&["devices", "-l"])?;
    let list: Vec<Value> = out
        .lines()
        .skip(1)
        .filter(|l| !l.trim().is_empty())
        .filter_map(|l| {
            let parts: Vec<&str> = l.split_whitespace().collect();
            let serial = *parts.first()?;
            let state = *parts.get(1)?;
            let model = parts
                .iter()
                .find_map(|p| p.strip_prefix("model:"))
                .map(|m| m.replace('_', " "))
                .unwrap_or_else(|| "Android phone".into());
            Some(json!({
                "serial": serial, "state": state, "model": model,
                "wifi": is_wifi(serial), "secure": is_secure(serial),
            }))
        })
        .collect();
    Ok(json!({ "devices": list, "recent": recent() }))
}

fn connect(addr: &str) -> Result<Value, String> {
    let addr = addr.trim();
    if addr.is_empty() {
        return Err("Type the phone address, for example 192.168.1.20:5555.".into());
    }
    let (_, out, err) = run_timeout(&["connect", addr], 12)?;
    let msg = format!("{out}{err}");
    if msg.contains("connected to") {
        remember(addr);
        Ok(json!({ "ok": true, "serial": addr }))
    } else {
        Err(format!("Could not connect: {}", tail(&msg)))
    }
}

fn pair(addr: &str, code: &str) -> Result<Value, String> {
    let (_, out, err) = run_timeout(&["pair", addr.trim(), code.trim()], 20)?;
    let msg = format!("{out}{err}");
    if msg.contains("Successfully paired") {
        Ok(json!({ "ok": true }))
    } else {
        Err(format!("Pairing failed: {}", tail(&msg)))
    }
}

fn disconnect(serial: &str) -> Result<Value, String> {
    let _ = run_timeout(&["disconnect", serial], 8)?;
    let _ = forget(serial);
    Ok(json!({ "ok": true }))
}

/// Turn off classic Wi-Fi adb (port 5555) on the phone: adb on the phone goes back to USB only.
fn wifi_off(serial: &str) -> Result<Value, String> {
    let (_, out, err) = run_timeout(&["-s", serial, "usb"], 10)?;
    let _ = run_timeout(&["disconnect", serial], 8);
    let _ = forget(serial);
    let msg = format!("{out}{err}");
    if msg.contains("restarting") || msg.trim().is_empty() {
        Ok(json!({ "ok": true }))
    } else {
        Err(format!("Could not turn off Wi-Fi adb: {}", tail(&msg)))
    }
}

/// Switch a USB phone to classic Wi-Fi adb on port 5555 and connect to it.
/// WARNING: this mode is not encrypted. The app asks the user to confirm first.
fn usb_to_wifi(serial: &str) -> Result<Value, String> {
    let (_, out, _) = run(&["-s", serial, "shell", "ip -f inet addr show wlan0"])?;
    let ip = out
        .split_whitespace()
        .skip_while(|w| *w != "inet")
        .nth(1)
        .and_then(|cidr| cidr.split('/').next())
        .map(String::from)
        .ok_or("The phone is not on Wi-Fi. Turn on Wi-Fi on the phone first.")?;
    let (ok, out, err) = run(&["-s", serial, "tcpip", "5555"])?;
    if !ok {
        return Err(tail(&format!("{out}{err}")));
    }
    let addr = format!("{ip}:5555");
    let mut last = String::new();
    for _ in 0..5 {
        thread::sleep(Duration::from_millis(1500));
        match connect(&addr) {
            Ok(v) => return Ok(v),
            Err(e) => last = e,
        }
    }
    Err(last)
}

fn mdns() -> Result<Value, String> {
    let (_, out, _) = run_timeout(&["mdns", "services"], 8)?;
    let items: Vec<Value> = out
        .lines()
        .filter_map(|l| {
            let f: Vec<&str> = l.split_whitespace().collect();
            if f.len() < 3 || !f[1].starts_with("_adb") {
                return None;
            }
            let kind = if f[1].contains("pairing") { "pair" } else { "connect" };
            Some(json!({ "name": f[0], "kind": kind, "addr": f[2] }))
        })
        .collect();
    Ok(json!({ "items": items }))
}

fn list_dir(serial: &str, path: &str) -> Result<Value, String> {
    let dir = format!("{}/", path.trim_end_matches('/'));
    let cmd = format!(
        "[ -d {q} ] || {{ echo NOTDIR; exit 0; }}; find {q} -mindepth 1 -maxdepth 1 -exec stat -c '%F|%s|%Y|%n' {{}} + 2>/dev/null",
        q = shq(&dir)
    );
    let (ok, out, err) = run(&["-s", serial, "shell", &cmd])?;
    if !ok && out.trim().is_empty() {
        return Err(tail(&format!("Could not read the phone: {err}")));
    }
    if out.trim() == "NOTDIR" {
        return Err(format!("This folder is not on the phone: {path}"));
    }
    let mut items: Vec<Value> = Vec::new();
    for line in out.lines() {
        let bits: Vec<&str> = line.splitn(4, '|').collect();
        if bits.len() != 4 {
            continue;
        }
        let name = bits[3].trim_end_matches('/').rsplit('/').next().unwrap_or("");
        if name.is_empty() || name.starts_with('.') {
            continue;
        }
        items.push(json!({
            "name": name,
            "path": format!("{dir}{name}"),
            "dir": bits[0].starts_with("directory"),
            "size": bits[1].parse::<u64>().unwrap_or(0),
            "mtime": bits[2].parse::<u64>().unwrap_or(0),
        }));
    }
    Ok(json!({ "items": items }))
}

fn pull(serial: &str, dest: &str, paths: &[String]) -> Result<Value, String> {
    fs::create_dir_all(dest).map_err(|e| format!("Could not make the Mac folder: {e}"))?;
    let (mut done, mut failed) = (vec![], vec![]);
    for p in paths {
        let (ok, out, err) = run(&["-s", serial, "pull", "-a", p, dest])?;
        let entry = json!({ "path": p, "msg": tail(if err.trim().is_empty() { &out } else { &err }) });
        if ok { done.push(entry) } else { failed.push(entry) }
    }
    Ok(json!({ "done": done, "failed": failed }))
}

fn push(serial: &str, dest: &str, files: &[String]) -> Result<Value, String> {
    let dest = format!("{}/", dest.trim_end_matches('/'));
    let (mut done, mut failed) = (vec![], vec![]);
    for f in files {
        let (ok, out, err) = run(&["-s", serial, "push", f, &dest])?;
        let entry = json!({ "path": f, "msg": tail(&format!("{err}{out}")) });
        if ok { done.push(entry) } else { failed.push(entry) }
    }
    Ok(json!({ "done": done, "failed": failed }))
}

/// Save the first `bytes` bytes of a phone file to `out` on the Mac (0 = the whole file).
/// Used for thumbnails: a JPEG keeps its small preview near the start.
fn head(serial: &str, path: &str, bytes: u64, out: &str) -> Result<Value, String> {
    let cmd = if bytes == 0 { format!("cat {}", shq(path)) } else { format!("head -c {bytes} {}", shq(path)) };
    let res = Command::new(adb()?)
        .args(["-s", serial, "exec-out", &cmd])
        .stdin(Stdio::null())
        .output()
        .map_err(|e| format!("could not start adb: {e}"))?;
    if !res.status.success() || res.stdout.is_empty() {
        return Err(tail(&format!("Could not read {path}: {}", String::from_utf8_lossy(&res.stderr))));
    }
    fs::write(out, &res.stdout).map_err(|e| e.to_string())?;
    Ok(json!({ "ok": true, "bytes": res.stdout.len() }))
}

// ---------- main ----------

fn dispatch(args: &[String]) -> Result<Value, String> {
    let a = |i: usize| args.get(i).map(String::as_str).ok_or_else(|| format!("missing argument {i}"));
    match a(0)? {
        "version" => Ok(json!({ "version": env!("CARGO_PKG_VERSION") })),
        "devices" => devices(),
        "mdns" => mdns(),
        "ls" => list_dir(a(1)?, a(2)?),
        "pull" => pull(a(1)?, a(2)?, &args[3..]),
        "push" => push(a(1)?, a(2)?, &args[3..]),
        "connect" => connect(a(1)?),
        "pair" => pair(a(1)?, a(2)?),
        "disconnect" => disconnect(a(1)?),
        "usb-to-wifi" => usb_to_wifi(a(1)?),
        "wifi-off" => wifi_off(a(1)?),
        "forget" => forget(a(1)?),
        "head" => head(a(1)?, a(2)?, a(3)?.parse().map_err(|_| "bytes must be a number")?, a(4)?),
        other => Err(format!("unknown command: {other}")),
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.is_empty() {
        eprintln!("usage: droiddock-engine <command> [args]   (see source header)");
        std::process::exit(2);
    }
    match dispatch(&args) {
        Ok(v) => println!("{v}"),
        Err(e) => {
            println!("{}", json!({ "error": e }));
            std::process::exit(1);
        }
    }
}
