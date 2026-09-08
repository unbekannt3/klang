fn main() {
    // Only lengths and presence — never the values.
    let report = |name: &str, v: String| {
        println!("{name:14} len={:<4} placeholder={}", v.len(), v.starts_with("PLACEHOLDER"));
    };
    report("device id", klang_core::embedded_config::stream_key_a());
    report("device secret", klang_core::embedded_config::stream_key_b());
    report("pkce id", klang_core::embedded_config::stream_key_c());
    report("pkce secret", klang_core::embedded_config::stream_key_d());
    println!("has_stream_keys={} has_pkce_keys={}",
        klang_core::embedded_config::has_stream_keys(),
        klang_core::embedded_config::has_pkce_keys());
}
