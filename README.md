# Cross-chain Rebase

1. A protocol that allows user to deposit into a vault and in return, receive rebase tokens that represent their underlying balance
2. Rebase token -> balanceOf function is dynamic to show the changing balance with time.
    - Balance increases linearly with time
    - mint tokens to ours users every time they perform an action (minting, burning, transfering, or ... briging)
3. Interest rate
    - Indivually set an interest rate for each user based on some global interest rate of the protocol at the time the user deposit into the vault.
    - This global interest rate can only decrease to incetivise/reward early adopters.
    - Increase token adoption
