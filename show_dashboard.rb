require "bundler/inline"
gemfile do
  gem "puma"
  gem "activesupport"
  gem "dotenv"
  gem "pry"                  # command line debugger
  gem "pry-byebug"           # provides next, continue, step for pry
  gem "pry-rails"            # automatically use pry on the console
  gem "stripe"
  gem "sinatra"
end

require "dotenv"
require "pry"
require "active_support"
require "active_support/core_ext"
require "sinatra/base"
Dotenv.load(".env")

Stripe.api_key = ENV["STRIPE_SECRET_KEY"]
Stripe.api_version = "2019-09-09"
STRIPE_CUSTOMER_ID = ENV["STRIPE_CUSTOMER_ID"]
STRIPE_SMS_PRODUCT_ID = ENV["STRIPE_SMS_PRODUCT_ID"]
STRIPE_NUMBER_PRODUCT_ID = ENV["STRIPE_NUMBER_PRODUCT_ID"]

unless defined? STRIPE_JS_HOST
  STRIPE_JS_HOST = "https://js.stripe.com".freeze
end

unless defined? STRIPE_CONNECT_HOST
  STRIPE_CONNECT_HOST = "https://connect.stripe.com".freeze
end

# Checklist
# Create a customer (if needed)
# Create product (if needed)
# Create price (if needed)
# Spin up server to render dashboard

if STRIPE_CUSTOMER_ID.blank?
  @customer = Stripe::Customer.create(
    email: "batman@gmail.com"
  )
end

if STRIPE_SMS_PRODUCT_ID.blank?
  product =
    Stripe::Product.create(name: "Sent SMS")
  puts "Created SMS product #{product.id}"
  STRIPE_SMS_PRODUCT_ID = product.id.freeze
end

if STRIPE_NUMBER_PRODUCT_ID.blank?
  product =
    Stripe::Product.create(name: "Provisioned Phone Numbers")
  puts "Created number product #{product.id}"
  STRIPE_NUMBER_PRODUCT_ID = product.id.freeze
end

class StripeDashboardServer < Sinatra::Base
  set :stripe_customer_id, STRIPE_CUSTOMER_ID

  before do
    @subscriptions = Stripe::Subscription.list(customer: settings.stripe_customer_id)
  end

  get "/" do

    puts "We have a visitor!"
    erb :dashboard, locals: {
    }
  end

  post "/customer-portal-link" do
    customer_id = params["customer_id"]
    settings.stripe_customer_id = customer_id

    customer_id = STRIPE_CUSTOMER_ID if customer_id.blank?

    dash_link = Stripe::BillingPortal::Session.create(
      customer: customer_id,
      return_url: "http://localhost:9292",
    )
    redirect dash_link.url
  end

  post "/start-a-subscription" do
    interval = params["interval"]
    text_price = params["text_price"]
    phone_number_price = params["phone_number_price"]

    text_price = create_price(
      product_id: STRIPE_SMS_PRODUCT_ID,
      unit_amount: text_price,
      interval: interval,
      nickname: "SMS",
    )
    number_price = create_price(
      product_id: STRIPE_NUMBER_PRODUCT_ID,
      unit_amount: phone_number_price,
      interval: interval,
      nickname: "Phone Numbers",
    )

    subscription = Stripe::Subscription.create(
      {
        customer: STRIPE_CUSTOMER_ID,
        items: [
          {
            price: text_price.id,
          },
          {
            price: number_price.id,
          },
        ],
      },
    )
    puts "created subscription #{subscription.id}"
    redirect "/"
  end

  post "/create-checkout-session" do
    interval = params["interval"]
    text_price = params["text_price"]
    phone_number_price = params["phone_number_price"]

    text_price = create_price(
      product_id: STRIPE_SMS_PRODUCT_ID,
      unit_amount: text_price,
      interval: interval,
      nickname: "SMS",
    )
    number_price = create_price(
      product_id: STRIPE_NUMBER_PRODUCT_ID,
      unit_amount: phone_number_price,
      interval: interval,
      nickname: "Phone Numbers",
    )

    session = Stripe::Checkout::Session.create(
      customer: settings.stripe_customer_id,
      success_url: "http://localhost:9292/",
      cancel_url: "http://localhost:9292/",
      payment_method_types: ["card"],
      mode: "subscription",
      line_items: [
        {
          price: text_price.id,
        },
        {
          price: number_price.id,
        },
      ],
    )
    puts "creating a checkout session"
    redirect session.url
  end

  post "/send-a-text" do
    item_id = params["item_id"]
    event_date = params["event_date"]
    amount = params["amount"]

    amount = 1 if amount.blank?
    event_date = Time.current if event_date.blank?

    usage_record = Stripe::SubscriptionItem.create_usage_record(
      item_id,
      quantity: amount,
      timestamp: event_date.to_i,
      action: "set",
    )
    puts "created usage record #{usage_record.id}"
    redirect "/"
  end

  private

  def create_price(product_id:, unit_amount:, interval:, nickname:)
    Stripe::Price.create(
      product: product_id,
      unit_amount: unit_amount,
      currency: "usd",
      recurring: {
        interval: interval,
        usage_type: "metered",
        aggregate_usage: "last_during_period",
      },
      nickname: nickname,
    )
  end

end
