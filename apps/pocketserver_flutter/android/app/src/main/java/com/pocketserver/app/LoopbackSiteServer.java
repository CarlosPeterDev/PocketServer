package com.pocketserver.app;

import java.io.BufferedInputStream;
import java.io.Closeable;
import java.io.IOException;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.ScheduledThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

/** Serves one selected HTML document on IPv4 loopback for the lifetime of the app. */
final class LoopbackSiteServer implements Closeable {
    static final int MAX_PAGE_BYTES = 1024 * 1024;
    private static final int MAX_HEADER_BYTES = 8192;
    private static final int REQUEST_TIMEOUT_MILLIS = 2000;

    private final ServerSocket listener;
    private final byte[] page;
    private final ScheduledThreadPoolExecutor requestTimer = new ScheduledThreadPoolExecutor(1);
    private volatile Socket activeClient;

    static LoopbackSiteServer start(byte[] html) throws IOException {
        if (html.length == 0 || html.length > MAX_PAGE_BYTES) {
            throw new IllegalArgumentException("HTML size is outside the supported range");
        }
        ServerSocket listener = new ServerSocket();
        try {
            listener.bind(new InetSocketAddress(
                    InetAddress.getByAddress(new byte[] {127, 0, 0, 1}), 0), 8);
            LoopbackSiteServer server = new LoopbackSiteServer(listener, html);
            new Thread(server::serve, "pocketserver-http").start();
            return server;
        } catch (IOException | RuntimeException error) {
            closeQuietly(listener);
            throw error;
        }
    }

    private LoopbackSiteServer(ServerSocket listener, byte[] page) {
        this.listener = listener;
        this.page = page.clone();
        requestTimer.setRemoveOnCancelPolicy(true);
    }

    String url() {
        return "http://" + host() + "/";
    }

    private String host() {
        return "127.0.0.1:" + listener.getLocalPort();
    }

    private void serve() {
        try {
            while (!listener.isClosed()) {
                try (Socket client = listener.accept()) {
                    activeClient = client;
                    if (listener.isClosed()) {
                        return;
                    }
                    ScheduledFuture<?> timeout = requestTimer.schedule(
                            () -> closeQuietly(client), REQUEST_TIMEOUT_MILLIS, TimeUnit.MILLISECONDS);
                    try {
                        respond(client);
                    } catch (IOException ignored) {
                        // An incomplete request or a disconnected client ends this connection.
                    } finally {
                        timeout.cancel(false);
                        activeClient = null;
                    }
                }
            }
        } catch (IOException ignored) {
            // A listener closed by the activity wakes accept().
        } finally {
            close();
            requestTimer.shutdownNow();
        }
    }

    private void respond(Socket client) throws IOException {
        // The request timer closes slow connections, including those that stop reading responses.
        byte[] header = new byte[MAX_HEADER_BYTES];
        int length = 0;
        BufferedInputStream in = new BufferedInputStream(client.getInputStream());
        while (length < header.length) {
            int value = in.read();
            if (value < 0) {
                return;
            }
            header[length++] = (byte) value;
            if (length >= 4 && header[length - 4] == '\r' && header[length - 3] == '\n'
                    && header[length - 2] == '\r' && header[length - 1] == '\n') {
                serveRequest(client.getOutputStream(),
                        new String(header, 0, length - 4, StandardCharsets.ISO_8859_1));
                return;
            }
        }
        writeResponse(client.getOutputStream(), "431 Request Header Fields Too Large", null, false);
    }

    private void serveRequest(OutputStream out, String header) throws IOException {
        String[] lines = header.split("\\r\\n", -1);
        String[] request = lines[0].split(" ", -1);
        boolean headOnly = request.length > 0 && request[0].equals("HEAD");
        if (request.length != 3 || !request[2].equals("HTTP/1.1")) {
            writeResponse(out, "400 Bad Request", null, headOnly);
            return;
        }
        String requestHost = null;
        for (int i = 1; i < lines.length; i++) {
            String line = lines[i];
            int separator = line.indexOf(':');
            if (separator <= 0) {
                writeResponse(out, "400 Bad Request", null, headOnly);
                return;
            }
            if (line.substring(0, separator).equalsIgnoreCase("Host")) {
                if (requestHost != null) {
                    writeResponse(out, "400 Bad Request", null, headOnly);
                    return;
                }
                requestHost = line.substring(separator + 1).trim();
            }
        }
        if (!host().equals(requestHost)) {
            writeResponse(out, "400 Bad Request", null, headOnly);
        } else if (!headOnly && !request[0].equals("GET")) {
            writeResponse(out, "405 Method Not Allowed", null, false);
        } else if (!request[1].equals("/") && !request[1].equals("/index.html")) {
            writeResponse(out, "404 Not Found", null, headOnly);
        } else {
            writeResponse(out, "200 OK", page, headOnly);
        }
    }

    private static void writeResponse(
            OutputStream out, String status, byte[] body, boolean headOnly) throws IOException {
        String headers = "HTTP/1.1 " + status + "\r\n"
                + "Content-Length: " + (body == null ? 0 : body.length) + "\r\n"
                + "Content-Type: text/html; charset=utf-8\r\n"
                + "Cache-Control: no-store\r\n"
                + "X-Content-Type-Options: nosniff\r\n"
                + "Referrer-Policy: no-referrer\r\n"
                + (status.startsWith("405") ? "Allow: GET, HEAD\r\n" : "")
                + "Connection: close\r\n\r\n";
        out.write(headers.getBytes(StandardCharsets.US_ASCII));
        if (!headOnly && body != null) {
            out.write(body);
        }
        out.flush();
    }

    @Override
    public void close() {
        closeQuietly(listener);
        closeQuietly(activeClient);
    }

    private static void closeQuietly(Closeable resource) {
        if (resource != null) {
            try {
                resource.close();
            } catch (IOException ignored) {
                // Closing is best-effort after a network error.
            }
        }
    }
}
