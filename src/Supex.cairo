// SPDX-License-Identifier: MIT
#[starknet::contract]
mod Supex {
    use core::array::ArrayTrait;
    use openzeppelin::access::accesscontrol::{AccessControlComponent, DEFAULT_ADMIN_ROLE};
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc20::{DefaultConfig, ERC20Component, ERC20HooksEmptyImpl};
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use starknet::event::EventEmitter;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ClassHash, ContractAddress, get_block_timestamp, get_caller_address};
    use supex::ISupex::ISupex;
    use supex::Types::{
        PaymentProcessed, StatusUpdated, Ticket, TicketCompleted, TicketCreated, TicketStatus,
    };
    use super::*;

    const UPGRADER_ROLE: felt252 = selector!("UPGRADER_ROLE");
    // const DEFAULT_ADMIN_ROLE: felt252 = selector!("DEFAULT_ADMIN_ROLE");
    const SHOP_OWNER_ROLE: felt252 = selector!("SHOP_OWNER_ROLE");

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    // External
    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    #[abi(embed_v0)]
    impl AccessControlMixinImpl =
        AccessControlComponent::AccessControlMixinImpl<ContractState>;

    // Internal
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        ticket_count: u64,
        tickets: Map<u64, Ticket>,
        shop_owners: Map<ContractAddress, bool>,
        shop_name: Map<ContractAddress, felt252>,
        shop_stats: Map<ContractAddress, (u64, u128)>, // (total_tickets, total_revenue)
        paused: bool,
        last_ticket_creation: Map<ContractAddress, u64>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        TicketCreated: TicketCreated,
        StatusUpdated: StatusUpdated,
        PaymentProcessed: PaymentProcessed,
        TicketCompleted: TicketCompleted,
    }

    const PLATFORM_FEE_BPS: u128 = 200;
    const BASE_FEE: u128 = 1000000000000000;
    const TIME_FEE_PER_SEC: u128 = 1000000000000;
    const RATE_LIMIT_SECONDS: u64 = 60;

    #[constructor]
    fn constructor(
        ref self: ContractState, default_admin: ContractAddress, upgrader: ContractAddress,
    ) {
        self.erc20.initializer("supex", "spk");
        self.accesscontrol.initializer();

        self.accesscontrol._grant_role(DEFAULT_ADMIN_ROLE, default_admin);
        self.accesscontrol._grant_role(UPGRADER_ROLE, upgrader);
        self.accesscontrol._grant_role(SHOP_OWNER_ROLE, default_admin);
    }

    #[abi(embed_v0)]
    impl SupexImpl of ISupex<ContractState> {
        fn register_shop_owner(ref self: ContractState, shop_name: felt252) {
            let caller = get_caller_address();
            self.shop_owners.write(caller, true);
            self.shop_name.write(caller, shop_name);
        }

        fn verify_shop_owner(self: @ContractState, owner_address: ContractAddress) -> bool {
            let is_shop_owner = self.shop_owners.read(owner_address);
            is_shop_owner
        }

        fn get_shop_statistics(self: @ContractState, shop_owner: ContractAddress) -> (u64, u128) {
            // NOTE: This will panic if shop_stats for shop_owner is not initialized.
            // Ensure it is initialized in mutating functions before calling this.
            self.shop_stats.read(shop_owner)
        }

        fn create_ticket(
            ref self: ContractState,
            customer_phone: felt252,
            gadget_type: felt252,
            estimated_duration: u64,
        ) -> u64 {
            assert(!self.paused.read(), 'Contract is paused');
            let caller = get_caller_address();
            let is_shop_owner = self.shop_owners.read(caller);
            assert!(is_shop_owner, "Only shop owners can create tickets");
            let now = get_block_timestamp();
            self.last_ticket_creation.write(caller, 0);
            let last_time = self.last_ticket_creation.read(caller);
            assert(now - last_time >= RATE_LIMIT_SECONDS, 'Rate limit exceeded');
            self.last_ticket_creation.write(caller, now);
            let id = self.ticket_count.read();
            // let payment_amount: u128 = BASE_FEE + u128_from_u64(estimated_duration) *
            // TIME_FEE_PER_SEC;
            let payment_amount: u128 = BASE_FEE + (estimated_duration.into()) * TIME_FEE_PER_SEC;

            let ticket = Ticket {
                ticket_id: id,
                customer_phone,
                gadget_type,
                shop_owner: caller,
                status: TicketStatus::Pending,
                created_at: now,
                updated_at: now,
                payment_amount,
                estimated_duration,
                escrowed: false,
            };
            self.tickets.write(id, ticket);
            self.ticket_count.write(id + 1);
            self.shop_stats.write(caller, (0, 0));
            let (total_tickets, total_revenue) = self.shop_stats.read(caller);
            self.shop_stats.write(caller, (total_tickets + 1, total_revenue));
            self.emit(TicketCreated { ticket_id: id, customer_phone, timestamp: now });
            id
        }

        fn update_ticket_status(ref self: ContractState, ticket_id: u64, new_status: TicketStatus) {
            assert(!self.paused.read(), 'Contract is paused');
            let caller = get_caller_address();
            let ticket = self.tickets.read(ticket_id);
            assert(ticket.shop_owner == caller, 'Only shop owner can update');
            let old_status = ticket.status;
            let now = get_block_timestamp();
            let updated_ticket = Ticket {
                ticket_id: ticket.ticket_id,
                customer_phone: ticket.customer_phone,
                gadget_type: ticket.gadget_type,
                shop_owner: ticket.shop_owner,
                status: new_status,
                created_at: ticket.created_at,
                updated_at: now,
                payment_amount: ticket.payment_amount,
                estimated_duration: ticket.estimated_duration,
                escrowed: ticket.escrowed,
            };
            self.tickets.write(ticket_id, updated_ticket);
            self.emit(StatusUpdated { ticket_id, old_status, new_status, timestamp: now });
            if new_status == TicketStatus::Collected {
                self.emit(TicketCompleted { ticket_id, completion_time: now });
            }
        }

        fn get_ticket_details(self: @ContractState, ticket_id: u64) -> Ticket {
            self.tickets.read(ticket_id)
        }

        fn cancel_ticket(ref self: ContractState, ticket_id: u64) {
            assert(!self.paused.read(), 'Contract is paused');
            let caller = get_caller_address();
            let ticket = self.tickets.read(ticket_id);
            assert(ticket.shop_owner == caller, 'Only shop owner can cancel');
            let cancelled_ticket = Ticket {
                ticket_id: ticket.ticket_id,
                customer_phone: ticket.customer_phone,
                gadget_type: ticket.gadget_type,
                shop_owner: ticket.shop_owner,
                status: TicketStatus::Cancelled,
                created_at: ticket.created_at,
                updated_at: get_block_timestamp(),
                payment_amount: ticket.payment_amount,
                estimated_duration: ticket.estimated_duration,
                escrowed: ticket.escrowed,
            };
            self.tickets.write(ticket_id, cancelled_ticket);
        }

        fn process_payment(ref self: ContractState, ticket_id: u64) {
            assert(!self.paused.read(), 'Contract is paused');
            let ticket = self.tickets.read(ticket_id);
            assert(ticket.status == TicketStatus::Pending, 'Payment only for pending');
            let updated_ticket = Ticket {
                ticket_id: ticket.ticket_id,
                customer_phone: ticket.customer_phone,
                gadget_type: ticket.gadget_type,
                shop_owner: ticket.shop_owner,
                status: TicketStatus::Charging,
                created_at: ticket.created_at,
                updated_at: get_block_timestamp(),
                payment_amount: ticket.payment_amount,
                estimated_duration: ticket.estimated_duration,
                escrowed: true,
            };
            self.tickets.write(ticket_id, updated_ticket);
            self
                .emit(
                    PaymentProcessed {
                        ticket_id, amount: ticket.payment_amount, shop_owner: ticket.shop_owner,
                    },
                );
        }

        fn release_payment(ref self: ContractState, ticket_id: u64) {
            assert(!self.paused.read(), 'Contract is paused');
            let ticket = self.tickets.read(ticket_id);
            assert(ticket.status == TicketStatus::Collected, 'Release only after collection');
            assert(ticket.escrowed, 'No escrowed payment');
            let platform_fee = ticket.payment_amount * PLATFORM_FEE_BPS / 10000;
            let shop_amount = ticket.payment_amount - platform_fee;
            self.shop_stats.write(ticket.shop_owner, (0, 0));
            let (total_tickets, total_revenue) = self.shop_stats.read(ticket.shop_owner);
            self.shop_stats.write(ticket.shop_owner, (total_tickets, total_revenue + shop_amount));
            let updated_ticket = Ticket {
                ticket_id: ticket.ticket_id,
                customer_phone: ticket.customer_phone,
                gadget_type: ticket.gadget_type,
                shop_owner: ticket.shop_owner,
                status: ticket.status,
                created_at: ticket.created_at,
                updated_at: get_block_timestamp(),
                payment_amount: ticket.payment_amount,
                estimated_duration: ticket.estimated_duration,
                escrowed: false,
            };
            self.tickets.write(ticket_id, updated_ticket);
        }

        fn refund_payment(ref self: ContractState, ticket_id: u64) {
            assert(!self.paused.read(), 'Contract is paused');
            let ticket = self.tickets.read(ticket_id);
            assert(ticket.status == TicketStatus::Cancelled, 'Refund only if cancelled');
            assert(ticket.escrowed, 'No escrowed payment');
            let updated_ticket = Ticket {
                ticket_id: ticket.ticket_id,
                customer_phone: ticket.customer_phone,
                gadget_type: ticket.gadget_type,
                shop_owner: ticket.shop_owner,
                status: ticket.status,
                created_at: ticket.created_at,
                updated_at: get_block_timestamp(),
                payment_amount: ticket.payment_amount,
                estimated_duration: ticket.estimated_duration,
                escrowed: false,
            };
            self.tickets.write(ticket_id, updated_ticket);
        }

        fn check_charging_status(self: @ContractState, ticket_id: u64) -> TicketStatus {
            let ticket = self.tickets.read(ticket_id);
            ticket.status
        }

        fn get_estimated_completion(self: @ContractState, ticket_id: u64) -> u64 {
            let ticket = self.tickets.read(ticket_id);
            ticket.created_at + ticket.estimated_duration
        }

        fn pause(ref self: ContractState) {
            self.paused.write(true);
        }

        fn unpause(ref self: ContractState) {
            self.paused.write(false);
        }

        fn batch_update_status(
            ref self: ContractState, ticket_ids: Array<u64>, new_status: TicketStatus,
        ) {
            assert(!self.paused.read(), 'Contract is paused');
            let caller = get_caller_address();
            let mut index = 0;
            while index < ticket_ids.len() {
                let ticket_id = *ticket_ids.at(index);
                let ticket = self.tickets.read(ticket_id);
                if ticket.shop_owner == caller {
                    let updated_ticket = Ticket {
                        ticket_id: ticket.ticket_id,
                        customer_phone: ticket.customer_phone,
                        gadget_type: ticket.gadget_type,
                        shop_owner: ticket.shop_owner,
                        status: new_status,
                        created_at: ticket.created_at,
                        updated_at: get_block_timestamp(),
                        payment_amount: ticket.payment_amount,
                        estimated_duration: ticket.estimated_duration,
                        escrowed: ticket.escrowed,
                    };
                    self.tickets.write(ticket_id, updated_ticket);
                }
                index += 1;
            }
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.accesscontrol.assert_only_role(UPGRADER_ROLE);
            self.upgradeable.upgrade(new_class_hash);
        }
    }
}
