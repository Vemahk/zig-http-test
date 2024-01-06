openssl req -x509 \
    -days 3650 -nodes \
    -newkey rsa:4096 \
    -keyout zig-out/vemahk.me.key \
    -out zig-out/vemahk.me.crt \
    -subj /CN=vemahk.me
#    -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
