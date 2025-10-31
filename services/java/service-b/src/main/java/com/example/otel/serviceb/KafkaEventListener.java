package com.example.otel.serviceb;

import lombok.extern.slf4j.Slf4j;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Service;

@Slf4j
@Service
public class KafkaEventListener {

    @KafkaListener(topics = "service-events", groupId = "service-b-group")
    public void listen(String message) {
        log.info("Service B: Received Kafka message: {}", message);

        try {
            // Simulate some processing
            Thread.sleep(100);

            // Process the message
            log.info("Service B: Successfully processed message");
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            log.error("Service B: Message processing interrupted", e);
        } catch (Exception e) {
            log.error("Service B: Error processing message", e);
        }
    }
}
