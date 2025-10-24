package com.example.otel.servicec;

import com.example.otel.servicec.entity.Order;
import com.example.otel.servicec.entity.User;
import com.example.otel.servicec.repository.OrderRepository;
import com.example.otel.servicec.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.LocalDateTime;
import java.util.*;
import java.util.concurrent.ThreadLocalRandom;

@Slf4j
@RestController
@RequestMapping("/api/data")
@RequiredArgsConstructor
public class DataController {

    private final Random random = new Random();
    private final UserRepository userRepository;
    private final OrderRepository orderRepository;

    @GetMapping("/user/{userId}")
    public ResponseEntity<Map<String, Object>> getUserData(@PathVariable String userId) {
        log.info("Service C: Fetching user data for userId: {}", userId);
        long startTime = System.currentTimeMillis();

        try {
            Long id = Long.parseLong(userId);
            User user = userRepository.findById(id).orElse(null);

            if (user == null) {
                log.warn("Service C: User not found for userId: {}", userId);
                Map<String, Object> errorResponse = new HashMap<>();
                errorResponse.put("error", "User not found");
                errorResponse.put("userId", userId);
                errorResponse.put("service", "service-c");
                return ResponseEntity.status(HttpStatus.NOT_FOUND).body(errorResponse);
            }

            long queryTime = System.currentTimeMillis() - startTime;
            Map<String, Object> response = new HashMap<>();
            response.put("service", "service-c");
            response.put("userId", user.getId());
            response.put("username", user.getUsername());
            response.put("email", user.getEmail());
            response.put("status", user.getStatus());
            response.put("createdAt", user.getCreatedAt().toString());
            response.put("updatedAt", user.getUpdatedAt().toString());
            response.put("queryTime", queryTime);
            response.put("timestamp", System.currentTimeMillis());

            log.info("Service C: Completed user data fetch for userId: {} in {}ms", userId, queryTime);
            return ResponseEntity.ok(response);
        } catch (NumberFormatException e) {
            log.error("Service C: Invalid userId format: {}", userId);
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("error", "Invalid userId format");
            errorResponse.put("userId", userId);
            errorResponse.put("service", "service-c");
            return ResponseEntity.badRequest().body(errorResponse);
        }
    }

    @GetMapping("/order/{orderId}")
    public ResponseEntity<Map<String, Object>> getOrderData(@PathVariable String orderId) {
        log.info("Service C: Fetching order data for orderId: {}", orderId);
        long startTime = System.currentTimeMillis();

        try {
            Long id = Long.parseLong(orderId);
            Order order = orderRepository.findById(id).orElse(null);

            if (order == null) {
                log.warn("Service C: Order not found for orderId: {}", orderId);
                Map<String, Object> errorResponse = new HashMap<>();
                errorResponse.put("error", "Order not found");
                errorResponse.put("orderId", orderId);
                errorResponse.put("service", "service-c");
                return ResponseEntity.status(HttpStatus.NOT_FOUND).body(errorResponse);
            }

            long queryTime = System.currentTimeMillis() - startTime;
            Map<String, Object> response = new HashMap<>();
            response.put("service", "service-c");
            response.put("orderId", order.getId());
            response.put("orderNumber", order.getOrderNumber());
            response.put("userId", order.getUserId());
            response.put("amount", order.getAmount());
            response.put("status", order.getStatus());
            response.put("items", order.getItemsCount());
            response.put("createdAt", order.getCreatedAt().toString());
            response.put("updatedAt", order.getUpdatedAt().toString());
            response.put("queryTime", queryTime);
            response.put("timestamp", System.currentTimeMillis());

            log.info("Service C: Completed order data fetch for orderId: {} in {}ms", orderId, queryTime);
            return ResponseEntity.ok(response);
        } catch (NumberFormatException e) {
            log.error("Service C: Invalid orderId format: {}", orderId);
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("error", "Invalid orderId format");
            errorResponse.put("orderId", orderId);
            errorResponse.put("service", "service-c");
            return ResponseEntity.badRequest().body(errorResponse);
        }
    }

    @GetMapping("/health")
    public Map<String, String> health() {
        Map<String, String> response = new HashMap<>();
        response.put("status", "UP");
        response.put("service", "service-c");
        return response;
    }

    // POST endpoints for creating data
    @PostMapping("/user")
    public ResponseEntity<Map<String, Object>> createUser(@RequestBody Map<String, String> userRequest) {
        log.info("Service C: Creating new user");
        long startTime = System.currentTimeMillis();

        try {
            String username = userRequest.get("username");
            String email = userRequest.get("email");
            String status = userRequest.getOrDefault("status", "active");

            if (username == null || email == null) {
                Map<String, Object> errorResponse = new HashMap<>();
                errorResponse.put("error", "Username and email are required");
                errorResponse.put("service", "service-c");
                return ResponseEntity.badRequest().body(errorResponse);
            }

            User user = new User();
            user.setUsername(username);
            user.setEmail(email);
            user.setStatus(status);

            User savedUser = userRepository.save(user);
            long queryTime = System.currentTimeMillis() - startTime;

            Map<String, Object> response = new HashMap<>();
            response.put("service", "service-c");
            response.put("userId", savedUser.getId());
            response.put("username", savedUser.getUsername());
            response.put("email", savedUser.getEmail());
            response.put("status", savedUser.getStatus());
            response.put("createdAt", savedUser.getCreatedAt().toString());
            response.put("queryTime", queryTime);
            response.put("timestamp", System.currentTimeMillis());

            log.info("Service C: Created user with id: {} in {}ms", savedUser.getId(), queryTime);
            return ResponseEntity.status(HttpStatus.CREATED).body(response);
        } catch (Exception e) {
            log.error("Service C: Error creating user", e);
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("error", "Failed to create user: " + e.getMessage());
            errorResponse.put("service", "service-c");
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorResponse);
        }
    }

    @PostMapping("/order")
    public ResponseEntity<Map<String, Object>> createOrder(@RequestBody Map<String, Object> orderRequest) {
        log.info("Service C: Creating new order");
        long startTime = System.currentTimeMillis();

        try {
            String orderNumber = (String) orderRequest.get("orderNumber");
            Long userId = orderRequest.get("userId") != null ?
                Long.parseLong(orderRequest.get("userId").toString()) : null;
            BigDecimal amount = orderRequest.get("amount") != null ?
                new BigDecimal(orderRequest.get("amount").toString()) : null;
            String status = (String) orderRequest.getOrDefault("status", "pending");
            Integer itemsCount = orderRequest.get("itemsCount") != null ?
                Integer.parseInt(orderRequest.get("itemsCount").toString()) : 1;

            if (orderNumber == null || userId == null || amount == null) {
                Map<String, Object> errorResponse = new HashMap<>();
                errorResponse.put("error", "orderNumber, userId, and amount are required");
                errorResponse.put("service", "service-c");
                return ResponseEntity.badRequest().body(errorResponse);
            }

            Order order = new Order();
            order.setOrderNumber(orderNumber);
            order.setUserId(userId);
            order.setAmount(amount);
            order.setStatus(status);
            order.setItemsCount(itemsCount);

            Order savedOrder = orderRepository.save(order);
            long queryTime = System.currentTimeMillis() - startTime;

            Map<String, Object> response = new HashMap<>();
            response.put("service", "service-c");
            response.put("orderId", savedOrder.getId());
            response.put("orderNumber", savedOrder.getOrderNumber());
            response.put("userId", savedOrder.getUserId());
            response.put("amount", savedOrder.getAmount());
            response.put("status", savedOrder.getStatus());
            response.put("items", savedOrder.getItemsCount());
            response.put("createdAt", savedOrder.getCreatedAt().toString());
            response.put("queryTime", queryTime);
            response.put("timestamp", System.currentTimeMillis());

            log.info("Service C: Created order with id: {} in {}ms", savedOrder.getId(), queryTime);
            return ResponseEntity.status(HttpStatus.CREATED).body(response);
        } catch (Exception e) {
            log.error("Service C: Error creating order", e);
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("error", "Failed to create order: " + e.getMessage());
            errorResponse.put("service", "service-c");
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorResponse);
        }
    }

    // Additional useful endpoints
    @GetMapping("/users")
    public ResponseEntity<Map<String, Object>> getAllUsers() {
        log.info("Service C: Fetching all users");
        long startTime = System.currentTimeMillis();

        List<User> users = userRepository.findAll();
        long queryTime = System.currentTimeMillis() - startTime;

        Map<String, Object> response = new HashMap<>();
        response.put("service", "service-c");
        response.put("users", users);
        response.put("count", users.size());
        response.put("queryTime", queryTime);
        response.put("timestamp", System.currentTimeMillis());

        log.info("Service C: Fetched {} users in {}ms", users.size(), queryTime);
        return ResponseEntity.ok(response);
    }

    @GetMapping("/orders")
    public ResponseEntity<Map<String, Object>> getAllOrders() {
        log.info("Service C: Fetching all orders");
        long startTime = System.currentTimeMillis();

        List<Order> orders = orderRepository.findAll();
        long queryTime = System.currentTimeMillis() - startTime;

        Map<String, Object> response = new HashMap<>();
        response.put("service", "service-c");
        response.put("orders", orders);
        response.put("count", orders.size());
        response.put("queryTime", queryTime);
        response.put("timestamp", System.currentTimeMillis());

        log.info("Service C: Fetched {} orders in {}ms", orders.size(), queryTime);
        return ResponseEntity.ok(response);
    }

    @GetMapping("/user/{userId}/orders")
    public ResponseEntity<Map<String, Object>> getUserOrders(@PathVariable String userId) {
        log.info("Service C: Fetching orders for userId: {}", userId);
        long startTime = System.currentTimeMillis();

        try {
            Long id = Long.parseLong(userId);
            List<Order> orders = orderRepository.findByUserId(id);
            long queryTime = System.currentTimeMillis() - startTime;

            Map<String, Object> response = new HashMap<>();
            response.put("service", "service-c");
            response.put("userId", id);
            response.put("orders", orders);
            response.put("count", orders.size());
            response.put("queryTime", queryTime);
            response.put("timestamp", System.currentTimeMillis());

            log.info("Service C: Fetched {} orders for userId: {} in {}ms", orders.size(), userId, queryTime);
            return ResponseEntity.ok(response);
        } catch (NumberFormatException e) {
            log.error("Service C: Invalid userId format: {}", userId);
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("error", "Invalid userId format");
            errorResponse.put("userId", userId);
            errorResponse.put("service", "service-c");
            return ResponseEntity.badRequest().body(errorResponse);
        }
    }
}

// Additional controller for non-data endpoints
@Slf4j
@RestController
@RequestMapping("/api")
class ServiceController {

    @GetMapping("/hello")
    public Map<String, Object> hello() {
        log.info("Service C: Received request at /api/hello");

        Map<String, Object> response = new HashMap<>();
        response.put("service", "service-c");
        response.put("message", "Hello from Service C");
        response.put("timestamp", System.currentTimeMillis());

        return response;
    }

    // CPU-intensive endpoint: Prime number calculation
    @GetMapping("/compute/primes/{limit}")
    public Map<String, Object> computePrimes(@PathVariable int limit) {
        log.info("Service C: Computing primes up to {}", limit);
        long startTime = System.currentTimeMillis();

        List<Integer> primes = new ArrayList<>();
        for (int num = 2; num <= limit; num++) {
            if (isPrime(num)) {
                primes.add(num);
            }
        }

        long duration = System.currentTimeMillis() - startTime;

        Map<String, Object> response = new HashMap<>();
        response.put("service", "service-c");
        response.put("operation", "prime-calculation");
        response.put("limit", limit);
        response.put("primesFound", primes.size());
        response.put("durationMs", duration);
        response.put("timestamp", System.currentTimeMillis());

        log.info("Service C: Found {} primes in {}ms", primes.size(), duration);
        return response;
    }

    // CPU-intensive endpoint: Hash computation
    @GetMapping("/compute/hash/{iterations}")
    public Map<String, Object> computeHash(@PathVariable int iterations) {
        log.info("Service C: Computing hash with {} iterations", iterations);
        long startTime = System.currentTimeMillis();

        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            String data = "ServiceC-" + System.currentTimeMillis();

            for (int i = 0; i < iterations; i++) {
                byte[] hash = digest.digest(data.getBytes(StandardCharsets.UTF_8));
                data = Base64.getEncoder().encodeToString(hash);
            }

            long duration = System.currentTimeMillis() - startTime;

            Map<String, Object> response = new HashMap<>();
            response.put("service", "service-c");
            response.put("operation", "hash-computation");
            response.put("iterations", iterations);
            response.put("finalHash", data.substring(0, 32));
            response.put("durationMs", duration);
            response.put("timestamp", System.currentTimeMillis());

            log.info("Service C: Hash computation completed in {}ms", duration);
            return response;
        } catch (Exception e) {
            log.error("Service C: Hash computation failed", e);
            throw new RuntimeException("Hash computation failed", e);
        }
    }

    // Memory-intensive endpoint: Large data structure creation
    @GetMapping("/memory/allocate/{sizeMb}")
    public Map<String, Object> allocateMemory(@PathVariable int sizeMb) {
        log.info("Service C: Allocating {}MB of memory", sizeMb);
        long startTime = System.currentTimeMillis();

        List<byte[]> dataList = new ArrayList<>();
        int chunks = sizeMb;

        for (int i = 0; i < chunks; i++) {
            byte[] chunk = new byte[1024 * 1024]; // 1MB
            ThreadLocalRandom.current().nextBytes(chunk);
            dataList.add(chunk);
        }

        long duration = System.currentTimeMillis() - startTime;

        Map<String, Object> response = new HashMap<>();
        response.put("service", "service-c");
        response.put("operation", "memory-allocation");
        response.put("allocatedMb", sizeMb);
        response.put("chunksCreated", dataList.size());
        response.put("durationMs", duration);
        response.put("timestamp", System.currentTimeMillis());

        dataList.clear();

        log.info("Service C: Allocated {}MB in {}ms", sizeMb, duration);
        return response;
    }

    // Memory-intensive endpoint: Large collection processing
    @GetMapping("/memory/process/{itemCount}")
    public Map<String, Object> processLargeCollection(@PathVariable int itemCount) {
        log.info("Service C: Processing {} items", itemCount);
        long startTime = System.currentTimeMillis();

        Map<String, String> largeMap = new HashMap<>();
        for (int i = 0; i < itemCount; i++) {
            largeMap.put("key-" + i, "value-" + UUID.randomUUID().toString());
        }

        long count = largeMap.values().stream()
            .filter(v -> v.contains("-"))
            .count();

        long duration = System.currentTimeMillis() - startTime;

        Map<String, Object> response = new HashMap<>();
        response.put("service", "service-c");
        response.put("operation", "collection-processing");
        response.put("itemsProcessed", itemCount);
        response.put("matchedItems", count);
        response.put("durationMs", duration);
        response.put("timestamp", System.currentTimeMillis());

        largeMap.clear();

        log.info("Service C: Processed {} items in {}ms", itemCount, duration);
        return response;
    }

    // Slow endpoint: Simulates database query
    @GetMapping("/slow/database/{delayMs}")
    public Map<String, Object> slowDatabase(@PathVariable int delayMs) {
        log.info("Service C: Simulating database query with {}ms delay", delayMs);
        long startTime = System.currentTimeMillis();

        try {
            Thread.sleep(delayMs);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            log.error("Service C: Sleep interrupted", e);
        }

        long duration = System.currentTimeMillis() - startTime;

        Map<String, Object> response = new HashMap<>();
        response.put("service", "service-c");
        response.put("operation", "database-query");
        response.put("expectedDelayMs", delayMs);
        response.put("actualDurationMs", duration);
        response.put("resultCount", ThreadLocalRandom.current().nextInt(1, 100));
        response.put("timestamp", System.currentTimeMillis());

        log.info("Service C: Database simulation completed in {}ms", duration);
        return response;
    }

    // Error simulation endpoint
    @GetMapping("/simulate/error")
    public Map<String, Object> simulateError() {
        log.warn("Service C: Simulating random error");

        int errorType = ThreadLocalRandom.current().nextInt(3);
        switch (errorType) {
            case 0:
                throw new RuntimeException("Simulated runtime exception");
            case 1:
                throw new IllegalStateException("Simulated illegal state");
            default:
                Map<String, Object> response = new HashMap<>();
                response.put("service", "service-c");
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
