package com.pocketserver.app;

import java.io.IOException;
import java.net.InetAddress;
import java.net.Socket;
import java.net.URI;
import java.nio.charset.StandardCharsets;

public final class LoopbackSiteServerSmoke {
    public static void main(String[] args) throws IOException {
        String html = "<!doctype html><title>PocketServer</title>";
        URI uri;
        try (LoopbackSiteServer server = LoopbackSiteServer.start(
                html.getBytes(StandardCharsets.UTF_8))) {
            uri = URI.create(server.url());
            require(uri.getHost().equals("127.0.0.1"), "Loopback address");
            String host = "Host: 127.0.0.1:" + uri.getPort() + "\r\n";
            String response = exchange(uri, "GET / HTTP/1.1\r\n" + host + "\r\n");
            require(response.startsWith("HTTP/1.1 200 ") && response.endsWith(html), "GET content");
            require(exchange(uri, "GET /index.html HTTP/1.1\r\n" + host + "\r\n")
                    .endsWith(html), "Index content");

            response = exchange(uri, "HEAD / HTTP/1.1\r\n" + host + "\r\n");
            require(response.startsWith("HTTP/1.1 200 ") && response.endsWith("\r\n\r\n")
                    && response.contains("Content-Length: " + html.length() + "\r\n"), "HEAD headers");

            expectStatus(uri, "POST / HTTP/1.1\r\n" + host + "\r\n", 405);
            expectStatus(uri, "GET /../secret HTTP/1.1\r\n" + host + "\r\n", 404);
            expectStatus(uri, "GET / HTTP/1.1\r\nHost: example.invalid\r\n\r\n", 400);
            expectStatus(uri, "GET / HTTP/1.1\r\n" + host + host + "\r\n", 400);
            expectStatus(uri, "x".repeat(8192), 431);
        }

        try {
            exchange(uri, "GET / HTTP/1.1\r\n\r\n");
            throw new AssertionError("Stopped server accepted a connection");
        } catch (java.net.ConnectException expected) {
            // Closing the server releases the port.
        }

        try {
            LoopbackSiteServer.start(new byte[LoopbackSiteServer.MAX_PAGE_BYTES + 1]);
            throw new AssertionError("Oversized page accepted");
        } catch (IllegalArgumentException expected) {
            // The byte limit is enforced before binding the listener.
        }

        System.out.println("Loopback server smoke checks passed.");
    }

    private static void expectStatus(URI uri, String request, int status) throws IOException {
        require(exchange(uri, request).startsWith("HTTP/1.1 " + status + " "), "Status " + status);
    }

    private static String exchange(URI uri, String request) throws IOException {
        try (Socket client = new Socket(InetAddress.getByName(uri.getHost()), uri.getPort())) {
            client.setSoTimeout(3000);
            client.getOutputStream().write(request.getBytes(StandardCharsets.US_ASCII));
            return new String(client.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
        }
    }

    private static void require(boolean condition, String label) {
        if (!condition) throw new AssertionError(label);
    }
}
