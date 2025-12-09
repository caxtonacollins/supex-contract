use starknet::ContractAddress;
use supex::Types::{Ticket, TicketStatus};

#[starknet::interface]
pub trait ISupex<TContractState> {
    fn register_shop_owner(ref self: TContractState, shop_name: felt252);
    fn verify_shop_owner(self: @TContractState, owner_address: ContractAddress) -> bool;
    fn get_shop_statistics(self: @TContractState, shop_owner: ContractAddress) -> (u64, u128);
    fn create_ticket(
        ref self: TContractState,
        customer_phone: felt252,
        gadget_type: felt252,
        estimated_duration: u64,
    ) -> u64;
    fn update_ticket_status(ref self: TContractState, ticket_id: u64, new_status: TicketStatus);
    fn get_ticket_details(self: @TContractState, ticket_id: u64) -> Ticket;
    fn cancel_ticket(ref self: TContractState, ticket_id: u64);
    fn process_payment(ref self: TContractState, ticket_id: u64);
    fn release_payment(ref self: TContractState, ticket_id: u64);
    fn refund_payment(ref self: TContractState, ticket_id: u64);
    fn check_charging_status(self: @TContractState, ticket_id: u64) -> TicketStatus;
    fn get_estimated_completion(self: @TContractState, ticket_id: u64) -> u64;
    fn pause(ref self: TContractState);
    fn unpause(ref self: TContractState);
    fn batch_update_status(
        ref self: TContractState, ticket_ids: Array<u64>, new_status: TicketStatus,
    );
}
