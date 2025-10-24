package com.example.otel.servicea;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestTemplate;

import java.util.*;
import java.util.concurrent.ThreadLocalRandom;
import java.security.MessageDigest;
import java.nio.charset.StandardCharsets;

@Slf4j
@RestController
@RequestMapping("/api")
public class FrontendController {

    @Autowired
    private RestTemplate restTemplate;

    @Value("${service.b.url:http://service-b:8081}")
    private String serviceBUrl;

    @GetMapping("/hello")
    public Map<String, Object> hello() {
        log.info("Service A: Received request at /api/hello");

        Map<String, Object> response = new HashMap<>();
        response.put("service", "service-a");
        response.put("message", "Hello from Service A");
        response.put("timestamp", System.currentTimeMillis());

        return response;
    }

    @GetMapping("/users/{userId}")
    public Map<String, Object> getUser(@PathVariable String userId) {
        log.info("Service A: Received request for user: {}", userId);

        // Call Service B
        String url = serviceBUrl + "/api/user/" + userId;
        log.info("Service A: Calling Service B at {}", url);

        Map<String, Object> serviceBResponse = restTemplate.getForObject(url, Map.class);

        Map<String, Object> response = new HashMap<>();
        response.put("service", "service-a");
        response.put("userId", userId);
        response.put("data", serviceBResponse);
        response.put("timestamp", System.currentTimeMillis());

        log.info("Service A: Returning response for user: {}", userId);
        return response;
    }

    @GetMapping("/orders/{orderId}")
    public Map<String, Object> getOrder(@PathVariable String orderId) {
        log.info("Service A: Received request for order: {}", orderId);

        // Call Service B
        String url = serviceBUrl + "/api/order/" + orderId;
        log.info("Service A: Calling Service B at {}", url);

        Map<String, Object> serviceBResponse = restTemplate.getForObject(url, Map.class);

        Map<String, Object> response = new HashMap<>();
        response.put("service", "service-a");
        response.put("orderId", orderId);
        response.put("data", serviceBResponse);
        response.put("timestamp", System.currentTimeMillis());

        log.info("Service A: Returning response for order: {}", orderId);
        return response;
    }

    @GetMapping("/health")
    public Map<String, String> health() {
        Map<String, String> response = new HashMap<>();
        response.put("status", "UP");
        response.put("service", "service-a");
        return response;
    }

    // CPU-intensive endpoint: Prime number calculation
    @GetMapping("/compute/primes/{limit}")
    public Map<String, Object> computePrimes(@PathVariable int limit) {
        log.info("Service A: Computing primes up to {}", limit);
        long startTime = System.currentTimeMillis();

        List<Integer> primes = new ArrayList<>();
        for (int num = 2; num <= limit; num++) {
            if (isPrime(num)) {
                primes.add(num);
            }
        }

        long duration = System.currentTimeMillis() - startTime;

        Map<String, Object> response = new HashMap<>();
        response.put("service", "service-a");
        response.put("operation", "prime-calculation");
        response.put("limit", limit);
        response.put("primesFound", primes.size());
        response.put("durationMs", duration);
        response.put("timestamp", System.currentTimeMillis());

        log.info("Service A: Found {} primes in {}ms", primes.size(), duration);
        return response;
    }

    // CPU-intensive endpoint: Hash computation
    @GetMapping("/compute/hash/{iterations}")
    public Map<String, Object> computeHash(@PathVariable int iterations) {
        log.info("Service A: Computing hash with {} iterations", iterations);
        long startTime = System.currentTimeMillis();

        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            String data = "ServiceA-" + System.currentTimeMillis();

            for (int i = 0; i < iterations; i++) {
                byte[] hash = digest.digest(data.getBytes(StandardCharsets.UTF_8));
                data = Base64.getEncoder().encodeToString(hash);
            }

            long duration = System.currentTimeMillis() - startTime;

            Map<String, Object> response = new HashMap<>();
            response.put("service", "service-a");
            response.put("operation", "hash-computation");
            response.put("iterations", iterations);
            response.put("finalHash", data.substring(0, 32));
            response.put("durationMs", duration);
            response.put("timestamp", System.currentTimeMillis());

            log.info("Service A: Hash computation completed in {}ms", duration);
            return response;
        } catch (Exception e) {
            log.error("Service A: Hash computation failed", e);
            throw new RuntimeException("Hash computation failed", e);
        }
    }

    // Memory-intensive endpoint: Large data structure creation
    @GetMapping("/memory/allocate/{sizeMb}")
    public Map<String, Object> allocateMemory(@PathVariable int sizeMb) {
        log.info("Service A: Allocating {}MB of memory", sizeMb);
        long startTime = System.currentTimeMillis();

        // Create large list to consume memory
        List<byte[]> dataList = new ArrayList<>();
        int chunks = sizeMb;

        for (int i = 0; i < chunks; i++) {
            byte[] chunk = new byte[1024 * 1024]; // 1MB
            ThreadLocalRandom.current().nextBytes(chunk);
            dataList.add(chunk);
        }

        long duration = System.currentTimeMillis() - startTime;

        Map<String, Object> response = new HashMap<>();
        response.put("service", "service-a");
        response.put("operation", "memory-allocation");
        response.put("allocatedMb", sizeMb);
        response.put("chunksCreated", dataList.size());
        response.put("durationMs", duration);
        response.put("timestamp", System.currentTimeMillis());

        // Keep reference briefly then let GC clean up
        dataList.clear();

        log.info("Service A: Allocated {}MB in {}ms", sizeMb, duration);
        return response;
    }

    // Memory-intensive endpoint: Large collection processing
    @GetMapping("/memory/process/{itemCount}")
    public Map<String, Object> processLargeCollection(@PathVariable int itemCount) {
        log.info("Service A: Processing {} items", itemCount);
        long startTime = System.currentTimeMillis();

        // Create large collection
        Map<String, String> largeMap = new HashMap<>();
        for (int i = 0; i < itemCount; i++) {
            largeMap.put("key-" + i, "value-" + UUID.randomUUID().toString());
        }

        // Process the collection
        long count = largeMap.values().stream()
            .filter(v -> v.contains("-"))
            .count();

        long duration = System.currentTimeMillis() - startTime;

        Map<String, Object> response = new HashMap<>();
        response.put("service", "service-a");
        response.put("operation", "collection-processing");
        response.put("itemsProcessed", itemCount);
        response.put("matchedItems", count);
        response.put("durationMs", duration);
        response.put("timestamp", System.currentTimeMillis());

        largeMap.clear();

        log.info("Service A: Processed {} items in {}ms", itemCount, duration);
        return response;
    }

    // Slow endpoint: Simulates database query
    @GetMapping("/slow/database/{delayMs}")
    public Map<String, Object> slowDatabase(@PathVariable int delayMs) {
        log.info("Service A: Simulating database query with {}ms delay", delayMs);
        long startTime = System.currentTimeMillis();

        try {
            Thread.sleep(delayMs);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            log.error("Service A: Sleep interrupted", e);
        }

        long duration = System.currentTimeMillis() - startTime;

        Map<String, Object> response = new HashMap<>();
        response.put("service", "service-a");
        response.put("operation", "database-query");
        response.put("expectedDelayMs", delayMs);
        response.put("actualDurationMs", duration);
        response.put("resultCount", ThreadLocalRandom.current().nextInt(1, 100));
        response.put("timestamp", System.currentTimeMillis());

        log.info("Service A: Database simulation completed in {}ms", duration);
        return response;
    }

    // Error simulation endpoint
    @GetMapping("/simulate/error")
    public Map<String, Object> simulateError() {
        log.warn("Service A: Simulating random error");

        int errorType = ThreadLocalRandom.current().nextInt(3);
        switch (errorType) {
            case 0:
                throw new RuntimeException("Simulated runtime exception");
            case 1:
                throw new IllegalStateException("Simulated illegal state");
            default:
                Map<String, Object> response = new HashMap<>();
                response.put("service", "service-a");
                response.put("error", "Simulated error response");
                response.put("timestamp", System.currentTimeMillis());
                return response;
        }
    }

    // Helper method to check if number is prime
    private boolean isPrime(int num) {
        if (num <= 1) return false;
        if (num == 2) return true;
        if (num % 2 == 0) return false;

        for (int i = 3; i * i <= num; i += 2) {
            if (num % i == 0) return false;
        }
        return true;
    }
}
