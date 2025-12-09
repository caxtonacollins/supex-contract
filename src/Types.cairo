use starknet::ContractAddress;

#[derive(Copy, Drop, Serde, starknet::Store, PartialEq)]
pub enum TicketStatus {
    #[default]
    Pending,
    Charging,
    Ready,
    Collected,
    Cancelled,
}

#[derive(Copy, Drop, Serde, PartialEq, starknet::Store, Clone)]
pub struct Ticket {
    pub ticket_id: u64,
    pub customer_phone: felt252,
    pub gadget_type: felt252,
    pub shop_owner: ContractAddress,
    pub status: TicketStatus,
    pub created_at: u64,
    pub updated_at: u64,
    pub payment_amount: u128,
    pub estimated_duration: u64,
    pub escrowed: bool,
}

#[derive(Drop, starknet::Event)]
pub struct TicketCreated {
    #[key]
    pub ticket_id: u64,
    pub customer_phone: felt252,
    pub timestamp: u64,
}

#[derive(Drop, starknet::Event)]
pub struct StatusUpdated {
    #[key]
    pub ticket_id: u64,
    pub old_status: TicketStatus,
    pub new_status: TicketStatus,
    pub timestamp: u64,
}

#[derive(Drop, starknet::Event)]
pub struct PaymentProcessed {
    #[key]
    pub ticket_id: u64,
    pub amount: u128,
    pub shop_owner: ContractAddress,
}

#[derive(Drop, starknet::Event)]
pub struct TicketCompleted {
    #[key]
    pub ticket_id: u64,
    pub completion_time: u64,
}
