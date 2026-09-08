package br.com.bookeasy.backend.Flat;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.UUID;

public interface FlatRepository extends JpaRepository<Flat, UUID> {
    
}
