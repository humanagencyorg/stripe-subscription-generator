# Stripe Subscription Generator

This is a quick and dirty Sinatra app that allows you to generate:
1. Multi product subscriptions with usage records
2. Customer Portal Sessions
3. Stripe Checkout Sessions

The purpose of this tool is to give you an opportunity to get hands on with Stripe subscription options.

## Running Locally

The following `ENV` variables are available for this project:
0. `STRIPE_SECRET_KEY` - Please keep this in your `.env` file.
1. `STRIPE_CUSTOMER_ID` - This will set a default customer on your Sinatra app so that you can quickly generate invoices.  A stripe customer can also be provided in the Sinatra interface.
2. `STRIPE_NUMBER_PRODUCT_ID` - This is the identification of the phone number product (or really any product) that you would like to use as a default.  If not provided, a new product will be generated for you.
3.`STRIPE_TEXT_PRODUCT_ID` - Same as last description... provides a default or will generate a new product for you.

To run the project:
```
rackup
```
