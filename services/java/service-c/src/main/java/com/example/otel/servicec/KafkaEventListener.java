package com.example.otel.servicec;

import lombok.extern.slf4j.Slf4j;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Service;

@Slf4j
@Service
public class KafkaEventListener {

    @KafkaListener(topics = "service-events", groupId = "service-c-group")
    public void listen(String message) {
        log.info("Service C: Received Kafka message: {}", message);

        try {
            // Simulate some processing
            Thread.sleep(150);

            // Process the message
            log.info("Service C: Successfully processed message");
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            log.error("Service C: Message processing interrupted", e);
        } catch (Exception e) {
            log.error("Service C: Error processing message", e);
        }
    }
}
